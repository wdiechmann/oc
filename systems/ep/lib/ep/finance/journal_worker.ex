defmodule Ep.Finance.JournalWorker do
  use Oban.Worker,
    queue: :projections,
    max_attempts: 10,
    unique: [period: 60, states: [:available, :scheduled, :retryable]]

  @impl true
  def perform(%Oban.Job{args: %{"tenant_id" => tid}}) do
    case Ep.Finance.JournalProjector.deliver(tid) do
      {:ok, _} -> :ok
      {:error, :view_stopped} -> {:snooze, 60}
      {:error, reason} -> {:error, reason}
    end
  end
end
