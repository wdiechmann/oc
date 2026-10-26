defmodule Ep.Monitoring.Maintenance do
  @moduledoc "Schedule approved retention work; production enablement is explicit."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_) do
    if Application.get_env(:ep, :monitoring_recovery_enabled, false),
      do: Process.send_after(self(), :recover, 1000)

    if Application.get_env(:ep, :monitoring_retention_enabled, false),
      do: Process.send_after(self(), :sweep, 1000)

    {:ok, nil}
  end

  @impl true
  def handle_info(:recover, state) do
    try do
      Ep.Monitoring.Projector.recover()
      Ep.Outbox.requeue_pending()
    rescue
      _ -> :ok
    end

    Process.send_after(self(), :recover, 60_000)
    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    try do
      Oban.insert(
        Ep.Monitoring.RetentionWorker.new(%{},
          unique: [period: 300, states: [:available, :scheduled, :executing, :retryable]]
        )
      )
    rescue
      _ -> :ok
    end

    Process.send_after(self(), :sweep, 300_000)
    {:noreply, state}
  end
end
