defmodule Ep.Monitoring.Observer do
  @moduledoc "Constant-cardinality telemetry counters; database work is never performed inside telemetry handlers."
  use GenServer
  import Ecto.Query

  @events [
    [:ep, :repo, :query],
    [:phoenix, :endpoint, :stop],
    [:oban, :job, :exception],
    [:oban, :job, :stop]
  ]
  @keys [:requests, :errors, :slow_requests, :database_errors, :pool_pressure, :exhausted_jobs]
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def flush(source_id), do: GenServer.call(__MODULE__, {:flush, source_id}, 5000)
  @impl true
  def init(_) do
    table = :ets.new(__MODULE__, [:public, :set, write_concurrency: true])
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, table)

    if Application.get_env(:ep, :monitoring_observer_enabled, false),
      do: Process.send_after(self(), :tick, 15_000)

    {:ok, %{table: table, open: %{}, last_recorded: %{}}}
  end

  def handle_event(event, measurements, metadata, table) do
    unless Process.get(:monitoring_internal) do
      case event do
        [:ep, :repo, :query] ->
          if match?({:error, _}, metadata[:result]), do: increment(table, :database_errors)

          if System.convert_time_unit(measurements[:queue_time] || 0, :native, :millisecond) > 100,
            do: increment(table, :pool_pressure)

        [:phoenix, :endpoint, :stop] ->
          conn = metadata[:conn]

          if conn && !String.starts_with?(conn.request_path, "/api/v1/monitoring") &&
               !String.starts_with?(conn.request_path, "/health") do
            increment(table, :requests)
            if conn.status && conn.status >= 500, do: increment(table, :errors)

            if System.convert_time_unit(measurements[:duration] || 0, :native, :millisecond) >
                 1000,
               do: increment(table, :slow_requests)
          end

        [:oban, :job, _] ->
          job = metadata[:job]

          if job && !String.starts_with?(job.worker, "Ep.Monitoring.") &&
               (metadata[:state] in [:discard, :discarded] ||
                  (metadata[:state] == :failure && job.attempt >= job.max_attempts)),
             do: increment(table, :exhausted_jobs)
      end
    end
  rescue
    ArgumentError -> :ok
  end

  defp increment(table, key), do: :ets.update_counter(table, key, {2, 1}, {key, 0})
  @impl true
  def handle_call(:snapshot, _, state),
    do: {:reply, Map.new(@keys, fn k -> {k, lookup(state.table, k)} end), state}

  def handle_call({:flush, source}, _, state) do
    {result, state} = collect(state, source)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:tick, state) do
    source = Application.get_env(:ep, :monitoring_source_id)
    {_, state} = if source, do: collect(state, source), else: {:ok, state}
    Process.send_after(self(), :tick, 15_000)
    {:noreply, state}
  end

  defp collect(state, source) do
    counters =
      Map.new(@keys, fn key ->
        value =
          case :ets.take(state.table, key) do
            [{_, n}] -> n
            _ -> 0
          end

        {key, value}
      end)

    Process.put(:monitoring_internal, true)

    conditions = %{
      "database.unavailable" => counters.database_errors > 0,
      "database.saturated" => counters.pool_pressure >= 10,
      "request.error_rate" =>
        counters.errors >= 10 && counters.errors / max(counters.requests, 1) >= 0.01,
      "request.latency_high" => counters.slow_requests >= 10,
      "job.exhausted" => counters.exhausted_jobs > 0
    }

    conditions =
      try do
        oldest =
          Ep.Repo.one(
            from o in Ep.Events.Outbox, where: is_nil(o.delivered_at), select: min(o.inserted_at)
          )

        pending = Ep.Repo.one(from p in Ep.Monitoring.Pending, select: min(p.inserted_at))

        lag =
          Enum.any?([oldest, pending], fn t -> t && DateTime.diff(DateTime.utc_now(), t) > 30 end)

        Map.put(conditions, "projection.delayed", lag)
      rescue
        _ -> Map.put(conditions, "database.unavailable", true)
      end

    state =
      Enum.reduce(conditions, state, fn {code, active}, acc ->
        now = System.monotonic_time(:second)
        was_open = Map.get(acc.open, code, false)
        last = Map.get(acc.last_recorded, code, now - 60)

        if (active && (!was_open || now - last >= 60)) || (!active && was_open) do
          observed_code = if active, do: code, else: "condition.recovered"

          input = %{
            "source_id" => source,
            "source_observation_id" => Ecto.UUID.generate(),
            "correlation_id" => Ecto.UUID.generate(),
            "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
            "code" => observed_code,
            "component" => String.replace(code, ".", "-")
          }

          try do
            case Ep.Monitoring.record("ep", input) do
              {:ok, _} -> :ok
              _ -> Ep.Monitoring.Spool.enqueue(input)
            end
          rescue
            _ -> Ep.Monitoring.Spool.enqueue(input)
          end

          %{
            acc
            | open: Map.put(acc.open, code, active),
              last_recorded: Map.put(acc.last_recorded, code, now)
          }
        else
          acc
        end
      end)

    {counters, state}
  after
    Process.delete(:monitoring_internal)
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{_, n}] -> n
      _ -> 0
    end
  end

  @impl true
  def terminate(_, state) do
    :telemetry.detach(__MODULE__)
    :ets.delete(state.table)
  end
end
