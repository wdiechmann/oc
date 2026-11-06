defmodule Ep.Finance.JournalPosting do
  @moduledoc "Explicitly confirmed, atomic EP journal posting and account impact."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{CommandReceipt, Details, Event, Outbox}
  alias Ep.Finance.{JournalDraft, Journals, JournalState, JournalWorker}
  @command_type "FinanceJournalWork:post"

  def impact(principal, tid, bid, id) do
    Journals.posting_scope(principal, tid, bid, false, fn tid, bid, book, steward, current ->
      plan!(tid, bid, book, id, current) |> Map.put("can_post", steward)
    end)
  end

  def post(principal, tid, bid, p, key, app \\ "internal") do
    Journals.posting_command_scope(principal, tid, bid, fn tid, bid, book ->
      unless is_map(p) &&
               Enum.sort(Map.keys(p)) ==
                 ~w(contexts digest draft_id expected_draft_version expected_version) &&
               is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
             do: Repo.rollback(:invalid_journal)

      Events.lock!("command:" <> principal.identity_id <> ":" <> @command_type <> ":" <> key)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, p, app}))

      case Repo.get_by(CommandReceipt,
             identity_id: principal.identity_id,
             command_type: @command_type,
             idempotency_key: key
           ) do
        %{fingerprint: ^fingerprint, result: result} ->
          Map.put(result, "replayed", true)

        nil ->
          current = Journals.posting_ready!(tid, bid, book)
          plan = plan!(tid, bid, book, p["draft_id"], current)

          unless plan["expected_version"] == p["expected_version"] &&
                   plan["expected_draft_version"] == p["expected_draft_version"] &&
                   plan["contexts"] === p["contexts"] && plan["digest"] == p["digest"],
                 do: Repo.rollback(:version_conflict)

          unless plan["errors"] == [], do: Repo.rollback(:journal_not_postable)
          draft = Repo.get!(JournalDraft, p["draft_id"])
          eid = Ecto.UUID.generate()
          cid = Ecto.UUID.generate()
          version = current["journal_version"] + 1
          now = DateTime.utc_now() |> DateTime.to_iso8601()

          data =
            Map.merge(draft.data, %{
              "posted" => true,
              "posted_at" => now,
              "posting_event_id" => eid,
              "authorized_by" => principal.identity_id,
              "verified_by" => principal.identity_id
            })

          draft =
            Repo.update!(
              Ecto.Changeset.change(draft,
                data: data,
                validation: plan["validation"],
                contexts: current["contexts"],
                version: version,
                actor_identity_id: principal.identity_id,
                application_id: app
              )
            )

          [event] =
            Events.append!(
              %{
                id: eid,
                scope: "tenant",
                scope_key: "tenant:" <> tid,
                tenant_id: tid,
                stream_type: "finance_journals",
                stream_id: bid,
                actor_identity_id: principal.identity_id,
                command_id: cid,
                correlation_id: cid
              },
              [
                {"JournalPosted",
                 %{
                   "draft" => Journals.posting_snapshot(draft),
                   "posting" =>
                     Map.take(
                       plan,
                       ~w(draft_id expected_draft_version expected_version contexts accounts validation digest)
                     ),
                   "confirmed_at" => now
                 }}
              ]
            )

          unless event.stream_version == version, do: Repo.rollback(:version_conflict)
          Repo.update!(Ecto.Changeset.change(Repo.get!(JournalState, bid), version: version))
          Repo.insert!(%Outbox{tenant_id: tid, event_id: eid})
          Oban.insert!(JournalWorker.new(%{tenant_id: tid}))

          result = %{
            "draft_id" => draft.id,
            "tenant_id" => tid,
            "book_id" => bid,
            "stream_version" => version,
            "command_id" => cid,
            "event_ids" => [eid],
            "posted" => true
          }

          Repo.insert!(%CommandReceipt{
            id: cid,
            identity_id: principal.identity_id,
            command_type: @command_type,
            idempotency_key: key,
            fingerprint: fingerprint,
            result: result
          })

          Map.put(result, "replayed", false)

        _ ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
  end

  defp plan!(tid, bid, book, id, current) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      draft =
        Repo.get_by(JournalDraft, id: id, tenant_id: tid, book_id: bid) ||
          Repo.rollback(:not_found)

      if draft.data["deleted"], do: Repo.rollback(:not_found)
      if draft.data["posted"], do: Repo.rollback(:journal_already_posted)
      validation = Journals.posting_validation(tid, bid, draft.data)
      preview = validation["posting_preview"]
      balances = balances(tid, bid)

      accounts =
        Enum.flat_map(preview["rows"], & &1["legs"])
        |> Enum.filter(& &1["account"])
        |> Enum.group_by(& &1["account"]["id"])
        |> Enum.map(fn {id, legs} ->
          change = Enum.sum(Enum.map(legs, &(&1["debit_minor"] - &1["credit_minor"])))
          before = Map.get(balances, id, 0)

          %{
            "account" => hd(legs)["account"],
            "prepost_minor" => before,
            "post_minor" => change,
            "postpost_minor" => before + change
          }
        end)
        |> Enum.sort_by(&{&1["account"]["number"], &1["account"]["id"]})

      errors =
        Enum.uniq(
          validation["errors"] ++
            Enum.flat_map(validation["lines"], &(&1["errors"] ++ &1["warnings"])) ++
            preview["errors"] ++
            if(book.accounting_authority == "ep", do: [], else: ["external_accounting_authority"])
        )

      plan = %{
        "tenant_id" => tid,
        "book_id" => bid,
        "draft_id" => id,
        "name" => draft.data["name"],
        "posting_date" => draft.data["posting_date"],
        "base_currency" => book.base_currency,
        "expected_version" => current["journal_version"],
        "expected_draft_version" => draft.version,
        "contexts" => current["contexts"],
        "accounts" => accounts,
        "errors" => errors,
        "validation" => validation
      }

      Map.put(
        plan,
        "digest",
        :crypto.hash(:sha256, :erlang.term_to_binary(plan)) |> Base.encode16(case: :lower)
      )
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  # Immutable JournalPosted facts are the ledger. Reads/rebuilds never execute commands.
  defp balances(tid, bid) do
    Repo.all(
      from e in Event,
        join: d in Details,
        on: d.event_id == e.id,
        where:
          e.tenant_id == ^tid and e.stream_id == ^bid and e.stream_type == "finance_journals" and
            e.event_type == "JournalPosted",
        select: d.payload
    )
    |> Enum.reduce(%{}, fn payload, totals ->
      Enum.reduce(payload["posting"]["accounts"], totals, fn row, totals ->
        Map.update(totals, row["account"]["id"], row["post_minor"], &(&1 + row["post_minor"]))
      end)
    end)
  end
end
