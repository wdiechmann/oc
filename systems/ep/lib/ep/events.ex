defmodule Ep.Events do
  @moduledoc "Internal transactional append primitive. No public raw-event ingestion."
  alias Ep.Events.{Details, Event, StreamHead}
  alias Ep.Repo

  def lock!(key) do
    unless Repo.in_transaction?(), do: raise("EP locks require a transaction")
    Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
    :ok
  end

  def append!(metadata, facts) do
    unless Repo.in_transaction?(), do: raise("EP appends require a transaction")

    metadata =
      case Process.get(:ep_correlation_id) do
        nil ->
          metadata

        id ->
          if metadata.stream_type == "monitoring_issue",
            do: metadata,
            else: Map.put(metadata, :correlation_id, id)
      end

    key = Map.take(metadata, [:scope_key, :stream_type, :stream_id])
    lock!("stream:" <> Enum.join([key.scope_key, key.stream_type, key.stream_id], ":"))
    head = Repo.get_by(StreamHead, key) || Repo.insert!(struct!(StreamHead, key))

    events =
      facts
      |> Enum.with_index(head.version + 1)
      |> Enum.map(fn {{type, payload}, version} ->
        attrs = Map.merge(metadata, %{stream_version: version, event_type: type})
        event = Repo.insert!(struct!(Event, attrs))
        Repo.insert!(%Details{event_id: event.id, payload: payload})

        if String.starts_with?(event.stream_type, "monitoring_"),
          do: Ep.Monitoring.Privacy.index!(event, payload)

        if String.starts_with?(event.stream_type, "monitoring_"),
          do: Ep.Monitoring.Privacy.on_append!(event)

        event
      end)

    head |> Ecto.Changeset.change(version: head.version + length(facts)) |> Repo.update!()
    events
  end
end
