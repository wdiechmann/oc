defmodule Ep.Repo.Migrations.BindSignInLinksToExistingIdentities do
  use Ecto.Migration

  def change do
    alter table(:magic_link) do
      add :existing_identity_id, references(:identity, type: :uuid)
    end

    create index(:magic_link, [:existing_identity_id])
  end
end
