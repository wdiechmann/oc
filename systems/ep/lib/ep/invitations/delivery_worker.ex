defmodule Ep.Invitations.DeliveryWorker do
  @moduledoc "Durable notification wakeup. Contains only an invitation ID, never credentials."
  use Oban.Worker, queue: :default, max_attempts: 10
  import Ecto.Query
  alias Ep.{Repo, Invitations.Invitation}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => id}}) do
    now = DateTime.utc_now()

    invitation =
      Repo.one(
        from(i in Invitation,
          join: t in Ep.Tenancy.Tenant,
          on: t.id == i.tenant_id,
          join: a in Ep.Tenancy.Access,
          on: a.tenant_id == i.tenant_id and a.identity_id == i.inviter_identity_id,
          join: sponsor in Ep.Auth.Identity,
          on: sponsor.id == i.inviter_identity_id,
          where:
            i.id == ^id and i.status == "pending" and i.expires_at > ^now and t.status == "active" and
              a.status == "active" and a.role == "tenant_admin" and sponsor.status == "active",
          select: {i, t.name}
        )
      )

    case invitation do
      nil ->
        :ok

      {i, name} ->
        case Application.get_env(:ep, :invitation_delivery) do
          nil ->
            {:error, :delivery_unavailable}

          adapter ->
            adapter.deliver(%{
              email: i.email,
              tenant_name: name,
              tenant_id: i.tenant_id,
              invitation_id: i.id,
              expires_at: i.expires_at,
              instructions:
                "Sign in to TOM using this email and accept the tenant-admin invitation."
            })
        end
    end
  end
end
