defmodule Ep.Finance.ChartOrder do
  @moduledoc "Reviewed position-only changes for a complete current chart. No account membership or accounting changes."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{CommandReceipt, Outbox}

  alias Ep.Finance.{
    Account,
    ChartImport,
    ChartImportCleanupWorker,
    Setup,
    SetupState,
    SetupView,
    SetupWorker
  }

  @command_type "FinanceChartOrder:accept"
  @max_rows 2000
  @fields ~w(id tenant_id book_id number name kind position active retired formula formula_refs vat_entry_id category_entry_id vat_entry_version category_entry_version vat_code category version actor_identity_id application_id)a

  def get(principal, tid, bid) do
    scoped(principal, tid, bid, fn tid, bid, book ->
      {version, view} = ready!(tid, bid)

      rows =
        Setup.normalize_accounts(view.data["accounts"]) |> Enum.reject(&(&1["retired"] == true))

      bounded!(rows)

      %{
        tenant_id: tid,
        book_id: bid,
        book_name: book.name,
        source_version: version,
        rows: Enum.map(rows, &Map.take(&1, ~w(id number name kind position active))),
        max_rows: @max_rows
      }
    end)
  end

  def preview(principal, tid, bid, params, app \\ "internal") do
    scoped(principal, tid, bid, fn tid, bid, book ->
      {version, _} = ready!(tid, bid)

      unless is_map(params) && Enum.sort(Map.keys(params)) == ~w(expected_version ordered_ids) &&
               is_integer(params["expected_version"]),
             do: Repo.rollback(:invalid_order)

      unless params["expected_version"] == version, do: Repo.rollback(:version_conflict)
      current = current(tid, bid)
      bounded!(current)
      ids = ids!(params["ordered_ids"], current)
      plan = plan(current, ids, version)
      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      review =
        Repo.insert!(%ChartImport{
          tenant_id: tid,
          book_id: bid,
          identity_id: principal.identity_id,
          application_id: app,
          expires_at: expires,
          data: %{
            "purpose" => "chart_order",
            "book_name" => book.name,
            "ordered_ids" => ids,
            "expected_version" => version,
            "plan" => plan,
            "digest" => digest({tid, bid, principal.identity_id, app, version, ids, plan})
          }
        })

      Oban.insert!(
        ChartImportCleanupWorker.new(%{import_id: review.id, tenant_id: tid},
          scheduled_at: expires
        )
      )

      present(review)
    end)
  end

  def review(principal, tid, bid, id, app \\ "internal") do
    scoped(principal, tid, bid, fn tid, bid, _ ->
      present(review!(principal, tid, bid, id, app))
    end)
  end

  def accept(principal, tid, bid, id, params, key, app \\ "internal") do
    scoped(principal, tid, bid, fn tid, bid, _ ->
      unless is_map(params) && Enum.sort(Map.keys(params)) == ~w(digest expected_version) &&
               is_binary(params["digest"]) && is_integer(params["expected_version"]) &&
               is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
             do: Repo.rollback(:invalid_review)

      Events.lock!("command:" <> principal.identity_id <> ":" <> @command_type <> ":" <> key)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, id, params, app}))

      case Repo.get_by(CommandReceipt,
             identity_id: principal.identity_id,
             command_type: @command_type,
             idempotency_key: key
           ) do
        %{fingerprint: ^fingerprint, result: result} ->
          Map.put(result, "replayed", true)

        nil ->
          review = review!(principal, tid, bid, id, app)
          if review.accepted_command_id, do: Repo.rollback(:review_already_accepted)
          unless review.data["digest"] == params["digest"], do: Repo.rollback(:digest_conflict)
          {version, _} = ready!(tid, bid)

          unless version == params["expected_version"] &&
                   version == review.data["expected_version"],
                 do: Repo.rollback(:version_conflict)

          current = current(tid, bid)
          ids = ids!(review.data["ordered_ids"], current)
          seeds = Map.new(review.data["plan"]["rows"], &{&1["account_id"], &1["event_id"]})
          rebuilt = plan(current, ids, version, seeds)
          unless rebuilt == review.data["plan"], do: Repo.rollback(:digest_conflict)
          accept!(principal, tid, bid, review, rebuilt, current, key, fingerprint, app)

        _ ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
  end

  defp accept!(principal, tid, bid, review, plan, current, key, fingerprint, app) do
    cid = Ecto.UUID.generate()
    Repo.query!("SET CONSTRAINTS finance_account_book_position_unique DEFERRED")
    accounts = Map.new(current, &{&1.id, &1})

    facts =
      plan["rows"]
      |> Enum.filter(& &1["changed"])
      |> Enum.map(fn row ->
        account =
          Repo.update!(
            Ecto.Changeset.change(accounts[row["account_id"]],
              position: row["after_position"],
              version: row["after_version"],
              actor_identity_id: principal.identity_id,
              application_id: app
            )
          )

        {row["event_id"], "AccountRevised",
         %{
           "tenant_id" => tid,
           "book_id" => bid,
           "order_review_id" => review.id,
           "review_digest" => review.data["digest"],
           "account" => Map.take(account, @fields)
         }}
      end)

    events =
      if facts == [],
        do: [],
        else:
          Events.append!(
            %{
              scope: "tenant",
              scope_key: "tenant:" <> tid,
              tenant_id: tid,
              stream_type: "finance_setup",
              stream_id: bid,
              actor_identity_id: principal.identity_id,
              command_id: cid,
              correlation_id: cid
            },
            facts
          )

    version =
      if events == [], do: review.data["expected_version"], else: List.last(events).stream_version

    unless version == review.data["expected_version"] + length(events),
      do: Repo.rollback(:version_conflict)

    Repo.update!(Ecto.Changeset.change(Repo.get!(SetupState, bid), version: version))
    Enum.each(events, &Repo.insert!(%Outbox{tenant_id: tid, event_id: &1.id}))
    if events != [], do: Oban.insert!(SetupWorker.new(%{tenant_id: tid}))

    result = %{
      "command_id" => cid,
      "tenant_id" => tid,
      "book_id" => bid,
      "review_id" => review.id,
      "stream_version" => version,
      "event_ids" => Enum.map(events, & &1.id),
      "changed_count" => plan["changed_count"]
    }

    Repo.insert!(%CommandReceipt{
      id: cid,
      identity_id: principal.identity_id,
      command_type: @command_type,
      idempotency_key: key,
      fingerprint: fingerprint,
      result: result
    })

    Repo.update!(Ecto.Changeset.change(review, accepted_command_id: cid))
    Map.put(result, "replayed", false)
  end

  defp plan(current, ids, version, seeds \\ %{}) do
    accounts = Map.new(current, &{&1.id, &1})

    {rows, _} =
      ids
      |> Enum.with_index(1)
      |> Enum.map_reduce(version, fn {id, index}, v ->
        account = accounts[id]
        position = index * 100
        changed = account.position != position
        next = if changed, do: v + 1, else: v

        {%{
           "account_id" => id,
           "number" => account.number,
           "name" => account.name,
           "kind" => account.kind,
           "before_position" => account.position,
           "after_position" => position,
           "before_version" => account.version,
           "after_version" => if(changed, do: next, else: account.version),
           "changed" => changed,
           "event_id" => if(changed, do: seeds[id] || Ecto.UUID.generate())
         }, next}
      end)

    %{
      "rows" => rows,
      "changed_count" => Enum.count(rows, & &1["changed"]),
      "row_count" => length(rows)
    }
  end

  defp ids!(ids, current) do
    unless is_list(ids) && length(ids) <= @max_rows && length(ids) == length(current),
      do: Repo.rollback(:invalid_order)

    ids =
      Enum.map(ids, fn id ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> id
          _ -> Repo.rollback(:invalid_order)
        end
      end)

    unless length(Enum.uniq(ids)) == length(ids) &&
             MapSet.new(ids) == MapSet.new(Enum.map(current, & &1.id)),
           do: Repo.rollback(:invalid_order)

    ids
  end

  defp current(tid, bid),
    do:
      Repo.all(
        from a in Account,
          where: a.tenant_id == ^tid and a.book_id == ^bid and not a.retired,
          order_by: [a.position, a.id]
      )

  defp bounded!(rows), do: if(length(rows) > @max_rows, do: Repo.rollback(:chart_too_large))

  defp ready!(tid, bid) do
    Setup.running!(tid)
    state = Repo.get(SetupState, bid)
    unless state && state.catalogues_initialized, do: Repo.rollback(:catalogue_not_initialized)
    view = Repo.get(SetupView, bid)
    unless view && view.source_version == state.version, do: Repo.rollback(:view_pending)
    {state.version, view}
  end

  defp scoped(principal, tid, bid, fun) do
    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid) do
      Repo.transaction(fn ->
        {book, _, steward} = Setup.authorize!(principal, tid, bid)
        unless steward, do: Repo.rollback(:not_found)
        fun.(tid, bid, book)
      end)
    end
  end

  defp review!(principal, tid, bid, id, app) do
    id =
      case uuid(id) do
        {:ok, id} -> id
        _ -> Repo.rollback(:not_found)
      end

    row =
      Repo.one(
        from r in ChartImport,
          where:
            r.id == ^id and r.tenant_id == ^tid and r.book_id == ^bid and
              r.identity_id == ^principal.identity_id and r.application_id == ^app,
          lock: "FOR UPDATE"
      ) || Repo.rollback(:not_found)

    unless row.data["purpose"] == "chart_order", do: Repo.rollback(:not_found)

    if DateTime.compare(row.expires_at, DateTime.utc_now()) != :gt,
      do: Repo.rollback(:review_expired)

    row
  end

  defp present(row),
    do: %{
      review_id: row.id,
      tenant_id: row.tenant_id,
      book_id: row.book_id,
      book_name: row.data["book_name"],
      expected_version: row.data["expected_version"],
      expires_at: row.expires_at,
      digest: row.data["digest"],
      plan: row.data["plan"],
      accepted_command_id: row.accepted_command_id
    }

  defp digest(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.encode16(case: :lower)

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
