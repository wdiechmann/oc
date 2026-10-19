defmodule Ep.Projections.TenantDirectoryProjector do
  @moduledoc "Idempotent local outbox consumer; per-event inbox is the durable checkpoint."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event, Outbox}
  alias Ep.Projections.{Control, Inbox, TenantDirectory}
  @consumer "tenant_directory:v1"

  def deliver(tenant_id) do
    Repo.transaction(fn ->
      Events.lock!("projection:tenant_directory:" <> tenant_id)

      control =
        Repo.one!(
          from(c in Control,
            where: c.tenant_id == ^tenant_id and c.name == "tenant_directory",
            lock: "FOR SHARE"
          )
        )

      if control.state == "stopped", do: Repo.rollback(:view_stopped)
      # Read committed rows by their actual pending state, never by a global ID watermark.
      pending =
        Repo.all(
          from(o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tenant_id and e.stream_type == "tenant" and is_nil(o.delivered_at),
            order_by: e.stream_version,
            select: {o, e}
          )
        )

      Enum.each(pending, fn {outbox, event} ->
        consume!(event)
        Repo.update!(Ecto.Changeset.change(outbox, delivered_at: DateTime.utc_now()))
      end)

      length(pending)
    end)
  end

  @doc "Operator-only rebuild of this non-effecting local projection. Does not publish or enqueue."
  def rebuild(tenant_id) do
    Repo.transaction(fn ->
      Events.lock!("projection:tenant_directory:" <> tenant_id)

      Repo.delete_all(
        from(i in Inbox, where: i.tenant_id == ^tenant_id and i.consumer == ^@consumer)
      )

      Repo.delete_all(from(v in TenantDirectory, where: v.tenant_id == ^tenant_id))

      Repo.all(
        from(e in Event,
          where: e.tenant_id == ^tenant_id and e.stream_type == "tenant",
          order_by: e.stream_version
        )
      )
      |> Enum.each(&consume!/1)

      :ok
    end)
  end

  defp consume!(event) do
    unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
      payload = Repo.get!(Details, event.id).payload
      apply_event!(event, payload)
      Repo.insert!(%Inbox{consumer: @consumer, event_id: event.id, tenant_id: event.tenant_id})
    end
  end

  defp apply_event!(
         %Event{schema_version: 1, event_type: "TenantCreated", stream_version: 1} = event,
         payload
       ) do
    Repo.insert!(%TenantDirectory{
      tenant_id: event.tenant_id,
      name: Map.fetch!(payload, "name"),
      source_version: event.stream_version,
      last_event_id: event.id
    })
  end

  defp apply_event!(%Event{schema_version: 1, event_type: "TenantAdminGranted"} = event, _payload) do
    row = Repo.get_by!(TenantDirectory, tenant_id: event.tenant_id)

    unless row.source_version + 1 == event.stream_version,
      do: raise("tenant projection stream gap")

    row
    |> Ecto.Changeset.change(source_version: event.stream_version, last_event_id: event.id)
    |> Repo.update!()
  end

  defp apply_event!(_, _), do: raise("unsupported tenant event or schema version")
end
