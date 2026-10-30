defmodule Ep.Finance.SetupProjector do
  @moduledoc "Replayable setup-only MV. No external execution."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event, Outbox}
  alias Ep.Finance.{Setup, SetupView, SetupWorker}
  alias Ep.Projections.Inbox
  @consumer "finance_setup:v1"
  @types ~w(FinanceStewardAssigned FinanceStewardRevoked OccasionBookBound OccasionBookUnbound AccountCreated AccountRevised AccountDeactivated AccountReactivated)

  def deliver(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-setup:" <> tid)
      Setup.running!(tid)

      rows =
        Repo.all(
          from o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tid and is_nil(o.delivered_at) and e.stream_type == "finance_setup",
            order_by: [e.stream_id, e.stream_version],
            limit: 1000,
            select: {o, e}
        )

      Enum.each(rows, fn {out, event} ->
        consume!(tid, event)
        Repo.update!(Ecto.Changeset.change(out, delivered_at: DateTime.utc_now()))
      end)

      if length(rows) == 1000, do: Oban.insert!(SetupWorker.new(%{tenant_id: tid}))
      length(rows)
    end)
  end

  def rebuild(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-setup:" <> tid)
      Repo.delete_all(from v in SetupView, where: v.tenant_id == ^tid)
      Repo.delete_all(from i in Inbox, where: i.tenant_id == ^tid and i.consumer == ^@consumer)

      Repo.all(
        from e in Event,
          where: e.tenant_id == ^tid and e.stream_type == "finance_setup",
          order_by: [e.stream_id, e.stream_version]
      )
      |> Enum.each(&consume!(tid, &1))

      :ok
    end)
  end

  defp consume!(tid, event) do
    unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
      row = Repo.get(SetupView, event.stream_id)
      checkpoint = if row, do: row.source_version, else: 0

      unless event.schema_version == 1 && event.tenant_id == tid && event.scope == "tenant" &&
               event.scope_key == "tenant:" <> tid && is_nil(event.occasion_id) &&
               event.event_type in @types && event.stream_version == checkpoint + 1,
             do: Repo.rollback(:projection_gap)

      payload = Repo.get!(Details, event.id).payload

      unless payload["tenant_id"] == tid && payload["book_id"] == event.stream_id,
        do: Repo.rollback(:projection_scope)

      attrs = %{
        book_id: event.stream_id,
        tenant_id: tid,
        source_version: event.stream_version,
        data: payload["setup"]
      }

      if row,
        do: Repo.update!(Ecto.Changeset.change(row, attrs)),
        else: Repo.insert!(struct!(SetupView, attrs))

      Repo.insert!(%Inbox{consumer: @consumer, tenant_id: tid, event_id: event.id})
    end
  end
end
