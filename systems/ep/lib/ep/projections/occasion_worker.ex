defmodule Ep.Projections.OccasionWorker do
  use Oban.Worker, queue: :projections, max_attempts: 10
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_id" => tenant_id}}) do
    case Ep.Projections.OccasionDirectoryProjector.deliver(tenant_id) do
      {:ok, _} -> :ok
      {:error, :view_stopped} -> {:snooze, 60}
      {:error, reason} -> {:error, reason}
    end
  end
end
