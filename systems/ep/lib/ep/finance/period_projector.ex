defmodule Ep.Finance.PeriodProjector do
  @moduledoc "Ordered period/history query projection. Replay never executes finance or external ledger operations."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event, Outbox}
  alias Ep.Finance.{Periods, PeriodView, PeriodWorker}
  alias Ep.Projections.Inbox
  @consumer "finance_periods:v1"

  def deliver(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-periods:" <> tid)
      Periods.running!(tid)

      rows =
        Repo.all(
          from o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tid and is_nil(o.delivered_at) and
                e.stream_type == "finance_periods",
            order_by: [e.stream_id, e.stream_version],
            limit: 1000,
            select: {o, e}
        )

      Enum.each(rows, fn {out, event} ->
        consume!(tid, event)
        Repo.update!(Ecto.Changeset.change(out, delivered_at: DateTime.utc_now()))
      end)

      if length(rows) == 1000, do: Oban.insert!(PeriodWorker.new(%{tenant_id: tid}))
      length(rows)
    end)
  end

  def rebuild(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-periods:" <> tid)
      Repo.delete_all(from v in PeriodView, where: v.tenant_id == ^tid)
      Repo.delete_all(from i in Inbox, where: i.tenant_id == ^tid and i.consumer == ^@consumer)

      Repo.all(
        from e in Event,
          where: e.tenant_id == ^tid and e.stream_type == "finance_periods",
          order_by: [e.stream_id, e.stream_version]
      )
      |> Enum.each(&consume!(tid, &1))

      :ok
    end)
  end

  defp consume!(tid, event) do
    unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
      row = Repo.get(PeriodView, event.stream_id)
      source = if row, do: row.source_version, else: 0

      unless event.schema_version == 1 && event.tenant_id == tid && event.scope == "tenant" &&
               event.scope_key == "tenant:" <> tid && is_nil(event.occasion_id) &&
               event.stream_version == source + 1,
             do: Repo.rollback(:projection_gap)

      period = Repo.get!(Details, event.id).payload["period"]

      unless period["tenant_id"] == tid && period["book_id"] == event.stream_id &&
               period["version"] == event.stream_version &&
               period["actor_identity_id"] == event.actor_identity_id,
             do: Repo.rollback(:projection_scope)

      periods = if row, do: row.data["periods"], else: []
      previous = Enum.find(periods, &(&1["id"] == period["id"]))
      transition = {event.event_type, previous && previous["status"], period["status"]}

      unless transition in [
               {"PeriodCreated", nil, "draft"},
               {"PeriodRevised", "draft", "draft"},
               {"PeriodOpened", "draft", "open"},
               {"PeriodClosed", "open", "closed"},
               {"PeriodReopened", "closed", "open"}
             ],
             do: Repo.rollback(:projection_transition)

      if previous && event.event_type != "PeriodRevised" &&
           Enum.any?(~w(name start_date end_date), &(previous[&1] != period[&1])),
         do: Repo.rollback(:projection_transition)

      if event.event_type == "PeriodCreated" && period["id"] != event.id,
        do: Repo.rollback(:projection_scope)

      if event.event_type == "PeriodReopened" &&
           (!is_binary(period["reason"]) || String.trim(period["reason"]) == ""),
         do: Repo.rollback(:projection_transition)

      history = if previous, do: previous["history"], else: []

      fact =
        Map.take(
          period,
          ~w(name start_date end_date status version actor_identity_id application_id reason)
        )
        |> Map.merge(%{
          "event_id" => event.id,
          "event_type" => event.event_type,
          "accepted_at" => DateTime.to_iso8601(event.inserted_at)
        })

      period = Map.put(period, "history", history ++ [fact])

      periods =
        [period | Enum.reject(periods, &(&1["id"] == period["id"]))]
        |> Enum.sort_by(&{&1["start_date"], &1["id"]})

      attrs = %{
        book_id: event.stream_id,
        tenant_id: tid,
        source_version: event.stream_version,
        data: %{"periods" => periods}
      }

      if row,
        do: Repo.update!(Ecto.Changeset.change(row, attrs)),
        else: Repo.insert!(struct!(PeriodView, attrs))

      Repo.insert!(%Inbox{consumer: @consumer, tenant_id: tid, event_id: event.id})
    end
  end
end
