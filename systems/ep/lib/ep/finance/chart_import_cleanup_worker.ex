defmodule Ep.Finance.ChartImportCleanupWorker do
  use Oban.Worker, queue: :projections, max_attempts: 10
  import Ecto.Query
  @impl true
  def perform(%Oban.Job{args: %{"import_id" => id, "tenant_id" => tid}}) do
    now = DateTime.utc_now()

    case Ep.Repo.transaction(fn ->
           upload =
             Ep.Repo.one(
               from i in Ep.Finance.ChartImport,
                 where: i.id == ^id and i.tenant_id == ^tid and i.expires_at <= ^now,
                 lock: "FOR UPDATE"
             )

           if upload do
             Ep.Events.lock!("enclosure-learning:" <> upload.book_id)

             Ep.Repo.delete_all(
               from r in Ep.Finance.EnclosureLearningRecord,
                 where: r.upload_id == ^id and r.tenant_id == ^tid and is_nil(r.attachment_id)
             )

             Ep.Repo.delete!(upload, log: false)
           end
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
