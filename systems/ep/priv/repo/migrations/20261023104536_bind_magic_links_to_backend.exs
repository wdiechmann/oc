defmodule Ep.Repo.Migrations.BindMagicLinksToBackend do
  use Ecto.Migration

  def change do
    alter table(:magic_link) do
      add :backend_id, :text, null: false, default: "internal"
    end

    # EP no longer owns user-facing delivery. Do not retry obsolete delivery jobs.
    execute "UPDATE oban_jobs SET state = 'cancelled', cancelled_at = timezone('UTC', now()) WHERE worker = 'Ep.Invitations.DeliveryWorker' AND state IN ('available', 'scheduled', 'retryable', 'executing', 'suspended')",
            "SELECT 1"
  end
end
