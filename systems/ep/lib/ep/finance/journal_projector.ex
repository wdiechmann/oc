defmodule Ep.Finance.JournalProjector do
  @moduledoc "Ordered unposted journal/history query projection. Replay never executes finance or external ledger operations."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event, Outbox}
  alias Ep.Finance.{Journals, JournalView, JournalWorker}
  alias Ep.Projections.Inbox
  @consumer "finance_journals:v1"

  def deliver(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-journals:" <> tid)
      Journals.running!(tid)

      rows =
        Repo.all(
          from o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tid and is_nil(o.delivered_at) and
                e.stream_type == "finance_journals",
            order_by: [e.stream_id, e.stream_version],
            limit: 1000,
            select: {o, e}
        )

      Enum.each(rows, fn {out, event} ->
        consume!(tid, event)
        Repo.update!(Ecto.Changeset.change(out, delivered_at: DateTime.utc_now()))
      end)

      if length(rows) == 1000, do: Oban.insert!(JournalWorker.new(%{tenant_id: tid}))
      length(rows)
    end)
  end

  def rebuild(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-journals:" <> tid)
      Repo.delete_all(from v in JournalView, where: v.tenant_id == ^tid)
      Repo.delete_all(from i in Inbox, where: i.tenant_id == ^tid and i.consumer == ^@consumer)

      Repo.all(
        from e in Event,
          where: e.tenant_id == ^tid and e.stream_type == "finance_journals",
          order_by: [e.stream_id, e.stream_version]
      )
      |> Enum.each(&consume!(tid, &1))

      :ok
    end)
  end

  defp consume!(tid, event) do
    unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
      row = Repo.get(JournalView, event.stream_id)
      source = if row, do: row.source_version, else: 0

      unless event.schema_version == 1 && event.tenant_id == tid && event.scope == "tenant" &&
               event.scope_key == "tenant:" <> tid && is_nil(event.occasion_id) &&
               event.stream_version == source + 1,
             do: Repo.rollback(:projection_gap)

      draft = Repo.get!(Details, event.id).payload["draft"]

      unless draft["tenant_id"] == tid && draft["book_id"] == event.stream_id &&
               draft["version"] == event.stream_version &&
               draft["actor_identity_id"] == event.actor_identity_id,
             do: Repo.rollback(:projection_scope)

      drafts = if row, do: row.data["drafts"], else: []
      previous = Enum.find(drafts, &(&1["id"] == draft["id"]))

      unless (event.event_type == "JournalDraftCreated" && !previous && draft["id"] == event.id) ||
               (event.event_type == "JournalDraftRevised" && previous),
             do: Repo.rollback(:projection_transition)

      history = if previous, do: previous["history"], else: []

      fact =
        Map.drop(draft, ~w(history tenant_id book_id))
        |> Map.merge(%{
          "event_id" => event.id,
          "event_type" => event.event_type,
          "accepted_at" => DateTime.to_iso8601(event.inserted_at)
        })

      draft = Map.put(draft, "history", history ++ [fact])

      drafts =
        [draft | Enum.reject(drafts, &(&1["id"] == draft["id"]))]
        |> Enum.sort_by(&{&1["data"]["posting_date"], &1["id"]})

      attrs = %{
        book_id: event.stream_id,
        tenant_id: tid,
        source_version: event.stream_version,
        data: %{"drafts" => drafts}
      }

      if row,
        do: Repo.update!(Ecto.Changeset.change(row, attrs)),
        else: Repo.insert!(struct!(JournalView, attrs))

      Repo.insert!(%Inbox{consumer: @consumer, tenant_id: tid, event_id: event.id})
    end
  end
end
