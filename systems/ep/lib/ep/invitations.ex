defmodule Ep.Invitations do
  @moduledoc "Verified-recipient tenant-admin invitations; invitation IDs are never credentials."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Auth.{Identity, Principal}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Invitations.Invitation
  alias Ep.Tenancy.{Access, Tenant}

  def invite(%Principal{} = principal, tenant_id, params, key) do
    with {:ok, tenant_id} <- uuid(tenant_id), {:ok, email} <- email(params["email"]) do
      command(
        principal,
        "InviteTenantAdmin",
        key,
        {tenant_id, email},
        fn identity ->
          tenant_admin!(tenant_id, identity.id)
        end,
        fn identity ->
          Events.lock!("admin-invitation:" <> tenant_id <> ":" <> email)
          now = DateTime.utc_now()

          if Repo.exists?(
               from(i in Invitation,
                 where:
                   i.tenant_id == ^tenant_id and i.email == ^email and i.status == "pending" and
                     i.expires_at > ^now
               )
             ),
             do: Repo.rollback(:already_invited)

          if Repo.exists?(
               from(a in Access,
                 join: i in Identity,
                 on: i.id == a.identity_id,
                 where:
                   a.tenant_id == ^tenant_id and a.role == "tenant_admin" and a.status == "active" and
                     i.email == ^email
               )
             ),
             do: Repo.rollback(:already_admin)

          invitation =
            Repo.insert!(%Invitation{
              tenant_id: tenant_id,
              email: email,
              inviter_identity_id: identity.id,
              expires_at: DateTime.add(now, 7 * 86_400, :second)
            })

          Oban.insert!(Ep.Invitations.DeliveryWorker.new(%{invitation_id: invitation.id}))

          {invitation,
           [
             {"TenantAdminInvitationCreated",
              %{
                "invitation_id" => invitation.id,
                "expires_at" => DateTime.to_iso8601(invitation.expires_at)
              }}
           ]}
        end
      )
    end
  end

  def revoke(%Principal{} = principal, tenant_id, id, key) do
    with {:ok, tenant_id} <- uuid(tenant_id), {:ok, id} <- uuid(id) do
      command(
        principal,
        "RevokeTenantAdminInvitation",
        key,
        {tenant_id, id},
        fn identity ->
          tenant_admin!(tenant_id, identity.id)
        end,
        fn _identity ->
          invitation = lock_invitation!(tenant_id, id)
          if invitation.status != "pending", do: Repo.rollback(:invitation_unavailable)

          invitation =
            Repo.update!(
              Ecto.Changeset.change(invitation, status: "revoked", revoked_at: DateTime.utc_now())
            )

          {invitation, [{"TenantAdminInvitationRevoked", %{"invitation_id" => invitation.id}}]}
        end
      )
    end
  end

  def accept(%Principal{} = principal, tenant_id, id, key) do
    with {:ok, tenant_id} <- uuid(tenant_id), {:ok, id} <- uuid(id) do
      command(
        principal,
        "AcceptTenantAdminInvitation",
        key,
        {tenant_id, id},
        fn identity ->
          active_tenant!(tenant_id)

          invitation =
            Repo.get_by(Invitation, tenant_id: tenant_id, id: id, email: identity.email)

          unless invitation, do: Repo.rollback(:not_found)
        end,
        fn identity ->
          invitation = lock_invitation!(tenant_id, id)

          unless invitation.email == identity.email && invitation.status == "pending" &&
                   DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt,
                 do: Repo.rollback(:invitation_unavailable)

          # A pending invitation cannot outlive its sponsor's current administrative authority.
          tenant_admin!(tenant_id, invitation.inviter_identity_id)

          sponsor =
            Repo.one(
              from(i in Identity,
                where: i.id == ^invitation.inviter_identity_id and i.status == "active",
                lock: "FOR SHARE"
              )
            )

          unless sponsor, do: Repo.rollback(:invitation_unavailable)
          Events.lock!("tenant-admin-grant:" <> tenant_id <> ":" <> identity.id)
          access = Repo.get_by(Access, tenant_id: tenant_id, identity_id: identity.id)

          if access && access.status == "active" && access.role == "tenant_admin",
            do: Repo.rollback(:already_admin)

          if access do
            Repo.update!(Ecto.Changeset.change(access, role: "tenant_admin", status: "active"))
          else
            Repo.insert!(%Access{
              tenant_id: tenant_id,
              identity_id: identity.id,
              role: "tenant_admin"
            })
          end

          invitation =
            Repo.update!(
              Ecto.Changeset.change(invitation,
                status: "accepted",
                accepted_at: DateTime.utc_now(),
                accepted_identity_id: identity.id
              )
            )

          {invitation,
           [
             {"TenantAdminInvitationAccepted",
              %{"invitation_id" => invitation.id, "identity_id" => identity.id}},
             {"TenantAdminGranted",
              %{
                "identity_id" => identity.id,
                "role" => "tenant_admin",
                "invitation_id" => invitation.id
              }}
           ]}
        end
      )
    end
  end

  def list_for_tenant(%Principal{} = principal, tenant_id) do
    with {:ok, tenant_id} <- uuid(tenant_id) do
      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        tenant_admin!(tenant_id, identity.id)

        invitations =
          Repo.all(
            from(i in Invitation,
              where: i.tenant_id == ^tenant_id,
              order_by: [desc: i.inserted_at, asc: i.id],
              limit: 100
            )
          )

        %{invitations: Enum.map(invitations, &present/1)}
      end)
    end
  end

  def incoming(%Principal{} = principal) do
    Repo.transaction(fn ->
      identity = Auth.lock_principal!(principal)
      now = DateTime.utc_now()

      rows =
        Repo.all(
          from(i in Invitation,
            join: t in Tenant,
            on: t.id == i.tenant_id,
            join: a in Access,
            on: a.tenant_id == i.tenant_id and a.identity_id == i.inviter_identity_id,
            join: sponsor in Identity,
            on: sponsor.id == i.inviter_identity_id,
            where:
              i.email == ^identity.email and i.status == "pending" and i.expires_at > ^now and
                t.status == "active" and a.role == "tenant_admin" and a.status == "active" and
                sponsor.status == "active",
            order_by: [desc: i.inserted_at, asc: i.id],
            limit: 100,
            select: {i, t.name}
          )
        )

      %{invitations: Enum.map(rows, fn {i, name} -> Map.put(present(i), :tenant_name, name) end)}
    end)
  end

  defp command(principal, type, key, attrs, authorize, apply) do
    if is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key) do
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({type, attrs}))

      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        authorize.(identity)
        Events.lock!("command:" <> identity.id <> ":" <> type <> ":" <> key)

        case Repo.get_by(CommandReceipt,
               identity_id: identity.id,
               command_type: type,
               idempotency_key: key
             ) do
          nil ->
            {invitation, facts} = apply.(identity)
            command_id = Ecto.UUID.generate()

            events =
              Events.append!(
                %{
                  scope: "tenant",
                  scope_key: "tenant:" <> invitation.tenant_id,
                  tenant_id: invitation.tenant_id,
                  stream_type: "tenant",
                  stream_id: invitation.tenant_id,
                  actor_identity_id: identity.id,
                  command_id: command_id,
                  correlation_id: command_id
                },
                facts
              )

            Enum.each(events, fn e ->
              Repo.insert!(%Outbox{event_id: e.id, tenant_id: e.tenant_id})
            end)

            Oban.insert!(Ep.Projections.TenantWorker.new(%{tenant_id: invitation.tenant_id}))

            result = %{
              "tenant_id" => invitation.tenant_id,
              "invitation_id" => invitation.id,
              "command_id" => command_id,
              "event_ids" => Enum.map(events, & &1.id),
              "status" => invitation.status,
              "expires_at" => DateTime.to_iso8601(invitation.expires_at)
            }

            Repo.insert!(%CommandReceipt{
              id: command_id,
              identity_id: identity.id,
              command_type: type,
              idempotency_key: key,
              fingerprint: fingerprint,
              result: result
            })

            %{result: result, replayed: false}

          %{fingerprint: ^fingerprint, result: result} ->
            %{result: result, replayed: true}

          _ ->
            Repo.rollback(:idempotency_conflict)
        end
      end)
    else
      {:error, :invalid_idempotency_key}
    end
  end

  defp active_tenant!(tenant_id) do
    unless Repo.one(
             from(t in Tenant,
               where: t.id == ^tenant_id and t.status == "active",
               lock: "FOR SHARE"
             )
           ),
           do: Repo.rollback(:not_found)
  end

  defp tenant_admin!(tenant_id, identity_id) do
    active_tenant!(tenant_id)

    unless Repo.one(
             from(a in Access,
               where:
                 a.tenant_id == ^tenant_id and a.identity_id == ^identity_id and
                   a.role == "tenant_admin" and a.status == "active",
               lock: "FOR SHARE"
             )
           ),
           do: Repo.rollback(:not_found)
  end

  defp lock_invitation!(tenant_id, id) do
    Repo.one(
      from(i in Invitation, where: i.tenant_id == ^tenant_id and i.id == ^id, lock: "FOR UPDATE")
    ) || Repo.rollback(:not_found)
  end

  defp present(i) do
    status =
      if i.status == "pending" && DateTime.compare(i.expires_at, DateTime.utc_now()) != :gt,
        do: "expired",
        else: i.status

    %{
      invitation_id: i.id,
      tenant_id: i.tenant_id,
      email: i.email,
      status: status,
      expires_at: i.expires_at
    }
  end

  defp email(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()

    if byte_size(value) <= 254 && Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, value),
      do: {:ok, value},
      else: {:error, :invalid_email}
  end

  defp email(_), do: {:error, :invalid_email}

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, value} -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end
end
