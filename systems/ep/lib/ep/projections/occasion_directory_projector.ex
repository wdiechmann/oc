defmodule Ep.Projections.OccasionDirectoryProjector do
  @moduledoc "Incremental per-occasion read models; durable inbox and outbox acknowledgment share a transaction."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event, Outbox}
  alias Ep.Occasions.Directory
  alias Ep.Projections.{Control, Inbox}
  @consumer "occasion_directory:v1"

  def deliver(tenant_id) do
    Repo.transaction(fn ->
      Events.lock!("projection:occasion_directory:" <> tenant_id)

      control =
        Repo.one(
          from(c in Control,
            where: c.tenant_id == ^tenant_id and c.name == "occasion_directory",
            lock: "FOR SHARE"
          )
        )

      if control && control.state == "stopped", do: Repo.rollback(:view_stopped)

      pending =
        Repo.all(
          from(o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tenant_id and e.stream_type == "occasion" and is_nil(o.delivered_at),
            order_by: [e.stream_id, e.stream_version],
            select: {o, e}
          )
        )

      Enum.each(pending, fn {outbox, event} ->
        unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
          apply_event!(event, Repo.get!(Details, event.id).payload)
          Repo.insert!(%Inbox{consumer: @consumer, event_id: event.id, tenant_id: tenant_id})
        end

        Repo.update!(Ecto.Changeset.change(outbox, delivered_at: DateTime.utc_now()))
      end)

      length(pending)
    end)
  end

  defp apply_event!(
         %Event{schema_version: 1, event_type: "OccasionCreated", stream_version: 1} = e,
         p
       ) do
    Repo.insert!(%Directory{
      tenant_id: e.tenant_id,
      occasion_id: e.occasion_id,
      name: Map.fetch!(p, "name"),
      slug: Map.fetch!(p, "slug"),
      status: Map.fetch!(p, "status"),
      recruitment_state: Map.fetch!(p, "recruitment_state"),
      expires_at: DateTime.from_iso8601(Map.fetch!(p, "expires_at")) |> elem(1),
      source_version: 1,
      last_event_id: e.id
    })
  end

  defp apply_event!(%Event{schema_version: 1, event_type: type} = e, _)
       when type in [
              "RecruitmentApplicationSubmitted",
              "OccasionAdminGranted",
              "OccasionAdminInvitationCreated",
              "OccasionAdminInvitationAccepted",
              "OccasionAdminInvitationRevoked"
            ] do
    row = Repo.get_by!(Directory, tenant_id: e.tenant_id, occasion_id: e.occasion_id)
    unless row.source_version + 1 == e.stream_version, do: raise("occasion projection stream gap")

    Repo.update!(
      Ecto.Changeset.change(row, source_version: e.stream_version, last_event_id: e.id)
    )
  end

  defp apply_event!(%Event{schema_version: 1, event_type: type} = e, p)
       when type in ["OccasionRecruitmentOpened", "OccasionRecruitmentClosed"] do
    row = Repo.get_by!(Directory, tenant_id: e.tenant_id, occasion_id: e.occasion_id)
    unless row.source_version + 1 == e.stream_version, do: raise("occasion projection stream gap")

    changes = [
      source_version: e.stream_version,
      last_event_id: e.id,
      recruitment_state: if(type == "OccasionRecruitmentOpened", do: "open", else: "closed")
    ]

    changes =
      if type == "OccasionRecruitmentOpened",
        do: Keyword.put(changes, :recruitment_config, Map.fetch!(p, "config")),
        else: changes

    Repo.update!(Ecto.Changeset.change(row, changes))
  end

  defp apply_event!(_, _), do: raise("unsupported occasion event or schema version")
end
