defmodule Ep.Finance.ChartImportCleanupWorker do
  use Oban.Worker, queue: :projections, max_attempts: 10
  import Ecto.Query
  @impl true
  def perform(%Oban.Job{args: %{"import_id" => id, "tenant_id" => tid}}) do
    now = DateTime.utc_now()

    Ep.Repo.delete_all(
      from i in Ep.Finance.ChartImport,
        where: i.id == ^id and i.tenant_id == ^tid and i.expires_at <= ^now
    )

    :ok
  end
end
