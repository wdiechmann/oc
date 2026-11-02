defmodule Ep.Finance.ChartImports do
  @moduledoc "Private bounded reviews, snapshot export and atomic chart acceptance. No journals or money movement."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{CommandReceipt, Outbox}

  alias Ep.Finance.{
    Account,
    ChartImport,
    ChartImportCleanupWorker,
    ChartImportPlan,
    Setup,
    SetupState,
    SetupView,
    SetupWorker
  }

  @columns ~w(schema_version tenant_id book_id source_version account_id account_version type number name vat_entry_id vat_code category_entry_id category_code position formula active)
  @max_rows 500
  @max_bytes 2_097_152
  @fields ~w(id tenant_id book_id number name kind position active formula formula_refs vat_entry_id category_entry_id vat_entry_version category_entry_version vat_code category version actor_identity_id application_id)a

  def info(principal, tid, bid) do
    with {:ok, data} <- Setup.get(principal, tid, bid) do
      {:ok,
       data
       |> Map.take([
         :tenant_id,
         :book_id,
         :book_name,
         :status,
         :source_version,
         :latest_version,
         :permissions,
         :catalogues_initialized
       ])
       |> Map.merge(%{columns: @columns, max_rows: @max_rows, max_bytes: @max_bytes})}
    end
  end

  def export(principal, tid, bid, params \\ %{}) do
    scoped(principal, tid, bid, false, fn tid, bid, book ->
      {version, view} = ready!(tid, bid)

      unless is_map(params) &&
               Enum.all?(params, fn {key, value} ->
                 key in ~w(q source_version) && is_binary(value)
               end),
             do: Repo.rollback(:invalid_upload)

      if params["source_version"] && params["source_version"] != to_string(version),
        do: Repo.rollback(:chart_changed)

      q = String.downcase(String.slice(params["q"] || "", 0, 120))
      entries = Map.new(view.data["catalogue_entries"] || [], &{&1["id"], &1})

      rows =
        Setup.normalize_accounts(view.data["accounts"])
        |> Enum.filter(&String.contains?(String.downcase("#{&1["number"]} #{&1["name"]}"), q))
        |> Enum.map(fn a ->
          vat = entries[a["vat_entry_id"]]
          category = entries[a["category_entry_id"]]

          record = %{
            "schema_version" => "1",
            "tenant_id" => tid,
            "book_id" => bid,
            "source_version" => version,
            "account_id" => a["id"],
            "account_version" => a["version"],
            "type" => a["kind"],
            "number" => a["number"],
            "name" => a["name"],
            "vat_entry_id" => a["vat_entry_id"],
            "vat_code" => vat && vat["code"],
            "category_entry_id" => a["category_entry_id"],
            "category_code" => category && category["code"],
            "position" => a["position"],
            "formula" => a["formula"],
            "active" => a["active"]
          }

          Enum.map(@columns, fn column ->
            case record[column] do
              nil -> ""
              value -> to_string(value)
            end
          end)
        end)

      %{
        tenant_id: tid,
        book_id: bid,
        book_name: book.name,
        source_version: version,
        scope: if(q == "", do: "whole_chart", else: "filtered"),
        query: q,
        row_count: length(rows),
        columns: @columns,
        rows: rows
      }
    end)
  end

  def upload(principal, tid, bid, params, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, _book ->
      ready!(tid, bid)
      unless valid_upload?(params), do: Repo.rollback(:invalid_upload)
      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      row =
        Repo.insert!(%ChartImport{
          tenant_id: tid,
          book_id: bid,
          identity_id: principal.identity_id,
          application_id: app,
          expires_at: expires,
          data:
            Map.merge(params, %{
              "mapping" => default_mapping(params["headers"]),
              "source_digest" => digest(params)
            })
        })

      Oban.insert!(
        ChartImportCleanupWorker.new(%{import_id: row.id, tenant_id: tid}, scheduled_at: expires)
      )

      present(row)
    end)
  end

  def get(principal, tid, bid, id, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, _ ->
      present(review!(principal, tid, bid, id, app))
    end)
  end

  def preview(principal, tid, bid, id, params, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, _ ->
      {version, _} = ready!(tid, bid)
      row = review!(principal, tid, bid, id, app)
      if row.accepted_command_id, do: Repo.rollback(:import_already_accepted)

      unless is_map(params) && Map.keys(params) == ["mapping"] &&
               valid_mapping?(params["mapping"], row.data["headers"]),
             do: Repo.rollback(:invalid_mapping)

      current = Repo.all(from a in Account, where: a.tenant_id == ^tid and a.book_id == ^bid)

      plan =
        ChartImportPlan.build(
          tid,
          bid,
          row.data["headers"],
          row.data["records"],
          params["mapping"],
          current,
          version
        )

      data =
        row.data
        |> Map.merge(%{
          "mapping" => params["mapping"],
          "plan" => plan,
          "expected_version" => version
        })

      data =
        Map.put(
          data,
          "digest",
          digest(
            {row.id, tid, bid, principal.identity_id, app, version, plan, params["mapping"],
             row.data["source_digest"]}
          )
        )

      Repo.update!(Ecto.Changeset.change(row, data: data)) |> present()
    end)
  end

  def accept(principal, tid, bid, id, params, key, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, _ ->
      unless is_map(params) && Enum.sort(Map.keys(params)) == ~w(digest expected_version) &&
               is_binary(params["digest"]) && is_integer(params["expected_version"]) &&
               is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
             do: Repo.rollback(:invalid_review)

      type = "FinanceChartImport:accept"
      Events.lock!("command:" <> principal.identity_id <> ":" <> type <> ":" <> key)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, id, params, app}))

      case Repo.get_by(CommandReceipt,
             identity_id: principal.identity_id,
             command_type: type,
             idempotency_key: key
           ) do
        %{fingerprint: ^fingerprint, result: result} ->
          Map.put(result, "replayed", true)

        nil ->
          row = review!(principal, tid, bid, id, app)
          if row.accepted_command_id, do: Repo.rollback(:import_already_accepted)
          unless row.data["digest"] == params["digest"], do: Repo.rollback(:digest_conflict)
          unless row.data["plan"] && row.data["plan"]["valid"], do: Repo.rollback(:invalid_review)
          {version, _view} = ready!(tid, bid)

          unless row.data["expected_version"] == version && params["expected_version"] == version,
            do: Repo.rollback(:version_conflict)

          current = Repo.all(from a in Account, where: a.tenant_id == ^tid and a.book_id == ^bid)
          ids = Map.new(row.data["plan"]["rows"], &{to_string(&1["line"]), &1["account_id"]})
          events = Map.new(row.data["plan"]["rows"], &{to_string(&1["line"]), &1["event_id"]})

          plan =
            ChartImportPlan.build(
              tid,
              bid,
              row.data["headers"],
              row.data["records"],
              row.data["mapping"],
              current,
              version,
              ids,
              events
            )

          unless plan == row.data["plan"], do: Repo.rollback(:digest_conflict)
          accept_plan!(principal, tid, bid, row, plan, key, fingerprint, app)

        _ ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
  end

  defp accept_plan!(principal, tid, bid, review, plan, key, fingerprint, app) do
    cid = Ecto.UUID.generate()
    Repo.query!("SET CONSTRAINTS finance_account_book_position_unique DEFERRED")

    facts =
      plan["rows"]
      |> Enum.reject(&(&1["operation"] == "unchanged"))
      |> Enum.map(fn change ->
        old = Repo.get_by(Account, tenant_id: tid, book_id: bid, id: change["account_id"])

        attrs =
          account_attrs(change["after"])
          |> Map.merge(%{
            tenant_id: tid,
            book_id: bid,
            actor_identity_id: principal.identity_id,
            application_id: app
          })

        reserved =
          Enum.uniq(
            Enum.reject([attrs.number | if(old, do: old.reserved_numbers, else: [])], &is_nil/1)
          )

        attrs = Map.put(attrs, :reserved_numbers, reserved)

        account =
          if old,
            do: Repo.update!(Ecto.Changeset.change(old, Map.delete(attrs, :id))),
            else: Repo.insert!(struct!(Account, attrs))

        type =
          cond do
            !old -> "AccountCreated"
            old.active && !account.active -> "AccountDeactivated"
            !old.active && account.active -> "AccountReactivated"
            true -> "AccountRevised"
          end

        {change["event_id"], type,
         %{
           "tenant_id" => tid,
           "book_id" => bid,
           "import_id" => review.id,
           "source_digest" => review.data["source_digest"],
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

    state = Repo.get!(SetupState, bid)
    version = if events == [], do: state.version, else: List.last(events).stream_version
    unless version == state.version + length(events), do: Repo.rollback(:version_conflict)
    Repo.update!(Ecto.Changeset.change(state, version: version))
    Enum.each(events, &Repo.insert!(%Outbox{tenant_id: tid, event_id: &1.id}))
    if events != [], do: Oban.insert!(SetupWorker.new(%{tenant_id: tid}))

    result = %{
      "command_id" => cid,
      "tenant_id" => tid,
      "book_id" => bid,
      "import_id" => review.id,
      "stream_version" => version,
      "event_ids" => Enum.map(events, & &1.id),
      "counts" => plan["counts"]
    }

    Repo.insert!(%CommandReceipt{
      id: cid,
      identity_id: principal.identity_id,
      command_type: "FinanceChartImport:accept",
      idempotency_key: key,
      fingerprint: fingerprint,
      result: result
    })

    Repo.update!(Ecto.Changeset.change(review, accepted_command_id: cid))
    Map.put(result, "replayed", false)
  end

  defp account_attrs(attrs) do
    Enum.reduce(@fields, %{}, fn key, acc ->
      if Map.has_key?(attrs, Atom.to_string(key)),
        do: Map.put(acc, key, attrs[Atom.to_string(key)]),
        else: acc
    end)
  end

  defp scoped(principal, tid, bid, configure, fun) do
    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid) do
      Repo.transaction(fn ->
        {book, _admin, steward} = Setup.authorize!(principal, tid, bid)
        if configure && !steward, do: Repo.rollback(:not_found)
        fun.(tid, bid, book)
      end)
    end
  end

  defp ready!(tid, bid) do
    Setup.running!(tid)
    state = Repo.get(SetupState, bid)
    unless state && state.catalogues_initialized, do: Repo.rollback(:catalogue_not_initialized)
    view = Repo.get(SetupView, bid)
    unless view && view.source_version == state.version, do: Repo.rollback(:view_pending)
    {state.version, view}
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

    if DateTime.compare(row.expires_at, DateTime.utc_now()) != :gt,
      do: Repo.rollback(:review_expired)

    row
  end

  defp present(row) do
    %{
      import_id: row.id,
      tenant_id: row.tenant_id,
      book_id: row.book_id,
      expires_at: row.expires_at,
      headers: row.data["headers"],
      sample: Enum.take(row.data["records"], 3),
      row_count: length(row.data["records"]),
      columns: @columns,
      mapping: row.data["mapping"],
      plan: row.data["plan"],
      digest: row.data["digest"],
      expected_version: row.data["expected_version"],
      accepted_command_id: row.accepted_command_id
    }
  end

  defp valid_upload?(%{"headers" => headers, "records" => records} = params) do
    Map.keys(params) |> Enum.sort() == ~w(headers records) && is_list(headers) &&
      length(headers) in 1..32 &&
      Enum.all?(headers, &(is_binary(&1) && String.trim(&1) != "" && byte_size(&1) <= 120)) &&
      length(Enum.uniq(headers)) == length(headers) && is_list(records) &&
      length(records) in 1..@max_rows &&
      Enum.all?(records, fn values ->
        is_list(values) && length(values) == length(headers) &&
          Enum.all?(values, &(is_binary(&1) && byte_size(&1) <= 10_000))
      end) && byte_size(Jason.encode!(params)) <= @max_bytes
  end

  defp valid_upload?(_), do: false

  defp valid_mapping?(mapping, headers) when is_map(mapping) do
    Enum.all?(mapping, fn {field, header} -> field in @columns && header in headers end) &&
      Enum.all?(~w(type name position), &Map.has_key?(mapping, &1)) &&
      length(Enum.uniq(Map.values(mapping))) == map_size(mapping)
  end

  defp valid_mapping?(_, _), do: false

  defp default_mapping(headers) do
    aliases = %{
      "type" => ~w(type kind row_type),
      "number" => ~w(number account_number),
      "name" => ~w(name account_name),
      "vat_code" => ~w(vat_code vat),
      "category_code" => ~w(category_code category)
    }

    Enum.reduce(@columns, %{}, fn field, mapping ->
      matches =
        Enum.filter(
          headers,
          &(String.downcase(String.replace(String.trim(&1), " ", "_")) in Map.get(
              aliases,
              field,
              [field]
            ))
        )

      if length(matches) == 1, do: Map.put(mapping, field, hd(matches)), else: mapping
    end)
  end

  defp digest(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> Base.encode16(case: :lower)

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
