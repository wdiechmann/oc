defmodule Ep.Projections.TenantWorker do
  @moduledoc "Durable wake-up for the local tenant-directory outbox consumer."
  use Oban.Worker, queue: :projections, max_attempts: 10
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_id" => tenant_id}}) do
    case Ep.Projections.TenantDirectoryProjector.deliver(tenant_id) do
      {:ok, _} -> :ok
      {:error, :view_stopped} -> {:snooze, 60}
      {:error, reason} -> {:error, reason}
    end
  end
end
