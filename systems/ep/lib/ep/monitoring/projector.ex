defmodule Ep.Monitoring.Projector do
  @moduledoc "Dedicated monitoring publication consumer. Applying retained facts never executes side effects."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{Details, Event}
  alias Ep.Monitoring.{Issue, Pending, Source, View}

  def deliver(issue_id) do
    Repo.transaction(fn ->
      Events.lock!("monitoring-projector:" <> issue_id)
      issue = Repo.get!(Issue, issue_id)
      source = Repo.get!(Source, issue.source_id)

      if source.tenant_id do
        control =
          Repo.one(
            from c in Ep.Projections.Control,
              where: c.tenant_id == ^source.tenant_id and c.name == "monitoring",
              lock: "FOR SHARE"
          )

        unless control && control.state == "running", do: Repo.rollback(:view_stopped)
      end

      items =
        Repo.all(
          from p in Pending,
            join: e in Event,
            on: e.id == p.event_id,
            join: d in Details,
            on: d.event_id == e.id,
            where: p.issue_id == ^issue_id,
            order_by: e.stream_version,
            limit: 1000,
            select: {p, e, d.payload}
        )

      Enum.each(items, fn {pending, event, payload} ->
        view = Repo.get(View, issue_id)
        current = if view, do: view.source_version, else: 0

        cond do
          event.stream_version <= current ->
            :ok

          event.stream_version != current + 1 ->
            Repo.rollback(:stream_gap)

          true ->
            put_view!(view, issue_id, event, "issue", payload["snapshot"])

            data =
              Map.put(
                payload["observation"] || payload["snapshot"],
                "event_type",
                event.event_type
              )

            kind = if payload["observation"], do: "observation", else: "lifecycle"
            put_view!(nil, event.id, event, kind, data)
        end

        Repo.delete!(pending)
      end)

      if length(items) == 1000, do: Oban.insert!(Ep.Monitoring.Worker.new(%{issue_id: issue_id}))
      length(items)
    end)
  end

  def recover do
    ids = Repo.all(from p in Pending, distinct: p.issue_id, select: p.issue_id, limit: 500)

    Enum.each(ids, fn id ->
      Oban.insert!(
        Ep.Monitoring.Worker.new(%{issue_id: id},
          unique: [period: 60, states: [:available, :scheduled, :retryable]]
        )
      )
    end)

    length(ids)
  end

  defp put_view!(view, id, event, kind, data) do
    attrs = %{
      issue_id: event.stream_id,
      tenant_id: event.tenant_id,
      occasion_id: event.occasion_id,
      kind: kind,
      source_version: event.stream_version,
      data: data
    }

    case view do
      nil -> Repo.insert!(struct!(View, Map.put(attrs, :id, id)))
      row -> Repo.update!(Ecto.Changeset.change(row, attrs))
    end
  end
end
