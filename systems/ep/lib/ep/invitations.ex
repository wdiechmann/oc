defmodule Ep.Invitations do
  @moduledoc "Verified-recipient tenant and occasion admin invitations; invitation IDs are never credentials."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Auth.{Identity, Principal}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Invitations.Invitation
  alias Ep.Tenancy.{Access, Tenant}

  def invite(%Principal{} = principal, tenant_id, params, key, occasion_id \\ nil) do
    with {:ok, tenant_id} <- uuid(tenant_id),
         {:ok, occasion_id} <- optional_uuid(occasion_id),
         {:ok, email} <- email(params["email"]) do
      command(
        principal,
        command_type("Invite", occasion_id),
        key,
        fingerprint_scope(tenant_id, occasion_id, email),
        fn identity ->
          manage!(tenant_id, occasion_id, identity.id)
        end,
        fn identity ->
          Events.lock!(
            "admin-invitation:" <> tenant_id <> ":" <> (occasion_id || "tenant") <> ":" <> email
          )

          now = DateTime.utc_now()

          if Repo.exists?(
               from(i in scoped(Invitation, occasion_id),
                 where:
                   i.tenant_id == ^tenant_id and i.email == ^email and i.status == "pending" and
                     i.expires_at > ^now
               )
             ),
             do: Repo.rollback(:already_invited)

          if existing_admin?(tenant_id, occasion_id, email), do: Repo.rollback(:already_admin)

          invitation =
            Repo.insert!(%Invitation{
              tenant_id: tenant_id,
              occasion_id: occasion_id,
              email: email,
              inviter_identity_id: identity.id,
              expires_at: DateTime.add(now, 7 * 86_400, :second)
            })

          {invitation,
           [
             {event_type("InvitationCreated", occasion_id),
              %{
                "invitation_id" => invitation.id,
                "expires_at" => DateTime.to_iso8601(invitation.expires_at)
              }}
           ]}
        end
      )
    end
  end

  def revoke(%Principal{} = principal, tenant_id, id, key, occasion_id \\ nil) do
    with {:ok, tenant_id} <- uuid(tenant_id),
         {:ok, id} <- uuid(id),
         {:ok, occasion_id} <- optional_uuid(occasion_id) do
      command(
        principal,
        command_type("Revoke", occasion_id),
        key,
        fingerprint_scope(tenant_id, occasion_id, id),
        fn identity ->
          manage!(tenant_id, occasion_id, identity.id)
        end,
        fn _identity ->
          invitation = lock_invitation!(tenant_id, occasion_id, id)
          if invitation.status != "pending", do: Repo.rollback(:invitation_unavailable)

          invitation =
            Repo.update!(
              Ecto.Changeset.change(invitation, status: "revoked", revoked_at: DateTime.utc_now())
            )

          {invitation,
           [{event_type("InvitationRevoked", occasion_id), %{"invitation_id" => invitation.id}}]}
        end
      )
    end
  end

  def accept(%Principal{} = principal, tenant_id, id, key, occasion_id \\ nil) do
    with {:ok, tenant_id} <- uuid(tenant_id),
         {:ok, id} <- uuid(id),
         {:ok, occasion_id} <- optional_uuid(occasion_id) do
      command(
        principal,
        command_type("Accept", occasion_id),
        key,
        fingerprint_scope(tenant_id, occasion_id, id),
        fn identity ->
          active_scope!(tenant_id, occasion_id)

          invitation =
            Repo.get_by(scoped(Invitation, occasion_id),
              tenant_id: tenant_id,
              id: id,
              email: identity.email
            )

          unless invitation, do: Repo.rollback(:not_found)
        end,
        fn identity ->
          invitation = lock_invitation!(tenant_id, occasion_id, id)

          unless invitation.email == identity.email && invitation.status == "pending" &&
                   DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt,
                 do: Repo.rollback(:invitation_unavailable)

          # A pending invitation cannot outlive its sponsor's current administrative authority.
          manage!(tenant_id, occasion_id, invitation.inviter_identity_id)

          sponsor =
            Repo.one(
              from(i in Identity,
                where: i.id == ^invitation.inviter_identity_id and i.status == "active",
                lock: "FOR SHARE"
              )
            )

          unless sponsor, do: Repo.rollback(:invitation_unavailable)
          grant!(tenant_id, occasion_id, identity.id)

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
             {event_type("InvitationAccepted", occasion_id),
              %{"invitation_id" => invitation.id, "identity_id" => identity.id}},
             {event_type("Granted", occasion_id),
              %{
                "identity_id" => identity.id,
                "role" => role(occasion_id),
                "invitation_id" => invitation.id
              }}
           ]}
        end
      )
    end
  end

  def list_for_tenant(%Principal{} = principal, tenant_id, occasion_id \\ nil) do
    with {:ok, tenant_id} <- uuid(tenant_id), {:ok, occasion_id} <- optional_uuid(occasion_id) do
      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        manage!(tenant_id, occasion_id, identity.id)

        invitations =
          Repo.all(
            from(i in scoped(Invitation, occasion_id),
              where: i.tenant_id == ^tenant_id,
              order_by: [desc: i.inserted_at, asc: i.id],
              limit: 100
            )
          )

        occasion_name =
          if occasion_id,
            do: Repo.get_by!(Ep.Occasions.Occasion, tenant_id: tenant_id, id: occasion_id).name

        %{invitations: Enum.map(invitations, &present/1), occasion_name: occasion_name}
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
              is_nil(i.occasion_id) and i.email == ^identity.email and i.status == "pending" and
                i.expires_at > ^now and
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

  def incoming_occasions(%Principal{} = principal) do
    Repo.transaction(fn ->
      identity = Auth.lock_principal!(principal)
      now = DateTime.utc_now()

      rows =
        Repo.all(
          from(i in Invitation,
            join: o in Ep.Occasions.Occasion,
            on: o.id == i.occasion_id and o.tenant_id == i.tenant_id,
            join: t in Tenant,
            on: t.id == i.tenant_id,
            join: sponsor in Identity,
            on: sponsor.id == i.inviter_identity_id,
            left_join: a in Access,
            on: a.tenant_id == i.tenant_id and a.identity_id == i.inviter_identity_id,
            left_join: g in Ep.Occasions.Admin,
            on:
              g.tenant_id == i.tenant_id and g.occasion_id == i.occasion_id and
                g.identity_id == ^identity.id,
            where:
              i.email == ^identity.email and t.status == "active" and
                o.status in ["draft", "active"] and
                ((i.status == "pending" and i.expires_at > ^now and sponsor.status == "active" and
                    a.status == "active" and a.role == "tenant_admin") or
                   (i.status == "accepted" and i.accepted_identity_id == ^identity.id and
                      g.status == "active")),
            order_by: [desc: i.inserted_at, asc: i.id],
            limit: 100,
            select: {i, t.name, o.name}
          )
        )

      %{
        invitations:
          Enum.map(rows, fn {i, tenant, occasion} ->
            present(i) |> Map.put(:tenant_name, tenant) |> Map.put(:occasion_name, occasion)
          end)
      }
    end)
  end

  def notification(id) do
    now = DateTime.utc_now()

    row =
      Repo.one(
        from(i in Invitation,
          join: t in Tenant,
          on: t.id == i.tenant_id,
          join: a in Access,
          on: a.tenant_id == i.tenant_id and a.identity_id == i.inviter_identity_id,
          join: sponsor in Identity,
          on: sponsor.id == i.inviter_identity_id,
          left_join: o in Ep.Occasions.Occasion,
          on: o.id == i.occasion_id and o.tenant_id == i.tenant_id,
          where:
            i.id == ^id and i.status == "pending" and i.expires_at > ^now and t.status == "active" and
              a.status == "active" and a.role == "tenant_admin" and sponsor.status == "active" and
              (is_nil(i.occasion_id) or (not is_nil(o.id) and o.status in ["draft", "active"])),
          select: {i, t.name, o.name}
        )
      )

    case row do
      nil ->
        :skip

      {i, tenant, occasion} ->
        {:ok,
         %{
           email: i.email,
           tenant_name: tenant,
           tenant_id: i.tenant_id,
           occasion_id: i.occasion_id,
           occasion_name: occasion,
           role: role(i.occasion_id),
           invitation_id: i.id,
           expires_at: i.expires_at,
           instructions:
             "Sign in to TOM using this email, open Invitations and accept the named role and scope."
         }}
    end
  end

  defp scoped(query, nil), do: from(i in query, where: is_nil(i.occasion_id))
  defp scoped(query, id), do: from(i in query, where: i.occasion_id == ^id)
  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(id), do: uuid(id)
  defp role(nil), do: "tenant_admin"
  defp role(_), do: "occasion_admin"
  defp event_type(suffix, nil), do: "TenantAdmin" <> suffix
  defp event_type(suffix, _), do: "OccasionAdmin" <> suffix
  defp command_type("Invite", nil), do: "InviteTenantAdmin"
  defp command_type("Invite", _), do: "InviteOccasionAdmin"
  defp command_type(verb, nil), do: verb <> "TenantAdminInvitation"
  defp command_type(verb, _), do: verb <> "OccasionAdminInvitation"
  defp fingerprint_scope(tenant, nil, value), do: {tenant, value}
  defp fingerprint_scope(tenant, occasion, value), do: {tenant, occasion, value}

  defp active_scope!(tenant, nil), do: active_tenant!(tenant)

  defp active_scope!(tenant, occasion) do
    active_tenant!(tenant)

    row =
      Repo.one(
        from(o in Ep.Occasions.Occasion,
          where: o.tenant_id == ^tenant and o.id == ^occasion and o.status in ["draft", "active"],
          lock: "FOR SHARE"
        )
      )

    unless row, do: Repo.rollback(:not_found)
  end

  defp manage!(tenant, occasion, identity) do
    active_scope!(tenant, occasion)
    tenant_admin!(tenant, identity)
  end

  defp existing_admin?(tenant, nil, email) do
    Repo.exists?(
      from(a in Access,
        join: i in Identity,
        on: i.id == a.identity_id,
        where:
          a.tenant_id == ^tenant and a.role == "tenant_admin" and a.status == "active" and
            i.email == ^email
      )
    )
  end

  defp existing_admin?(tenant, occasion, email) do
    Repo.exists?(
      from(a in Ep.Occasions.Admin,
        join: i in Identity,
        on: i.id == a.identity_id,
        where:
          a.tenant_id == ^tenant and a.occasion_id == ^occasion and a.status == "active" and
            i.email == ^email
      )
    )
  end

  defp grant!(tenant, occasion, identity) do
    Events.lock!("admin-grant:" <> tenant <> ":" <> (occasion || "tenant") <> ":" <> identity)

    {schema, attrs} =
      if occasion,
        do:
          {Ep.Occasions.Admin, [tenant_id: tenant, occasion_id: occasion, identity_id: identity]},
        else: {Access, [tenant_id: tenant, identity_id: identity]}

    access = Repo.get_by(schema, attrs)

    if access && access.status == "active" &&
         (not is_nil(occasion) || access.role == "tenant_admin"),
       do: Repo.rollback(:already_admin)

    changes =
      if occasion, do: %{status: "active"}, else: %{status: "active", role: "tenant_admin"}

    if access,
      do: Repo.update!(Ecto.Changeset.change(access, changes)),
      else: Repo.insert!(struct!(schema, Map.merge(Map.new(attrs), changes)))
  end

  defp command(principal, type, key, attrs, authorize, apply) do
    if is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key) do
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({type, attrs}))

      transaction =
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

              metadata = %{
                scope: "tenant",
                scope_key: "tenant:" <> invitation.tenant_id,
                tenant_id: invitation.tenant_id,
                stream_type: "tenant",
                stream_id: invitation.tenant_id,
                actor_identity_id: identity.id,
                command_id: command_id,
                correlation_id: command_id
              }

              metadata =
                if invitation.occasion_id,
                  do:
                    Map.merge(metadata, %{
                      scope: "occasion",
                      scope_key:
                        "tenant:" <>
                          invitation.tenant_id <> ":occasion:" <> invitation.occasion_id,
                      occasion_id: invitation.occasion_id,
                      stream_type: "occasion",
                      stream_id: invitation.occasion_id
                    }),
                  else: metadata

              events = Events.append!(metadata, facts)

              Enum.each(events, fn e ->
                Repo.insert!(%Outbox{event_id: e.id, tenant_id: e.tenant_id})
              end)

              worker =
                if invitation.occasion_id,
                  do: Ep.Projections.OccasionWorker,
                  else: Ep.Projections.TenantWorker

              Oban.insert!(worker.new(%{tenant_id: invitation.tenant_id}))

              result = %{
                "tenant_id" => invitation.tenant_id,
                "occasion_id" => invitation.occasion_id,
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

      case transaction do
        {:ok, %{result: result} = accepted}
        when type in ["InviteTenantAdmin", "InviteOccasionAdmin"] ->
          delivery =
            case notification(result["invitation_id"]) do
              {:ok, message} -> message
              :skip -> nil
            end

          {:ok, Map.put(accepted, :delivery, delivery)}

        other ->
          other
      end
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

  defp lock_invitation!(tenant_id, occasion_id, id) do
    Repo.one(
      from(i in scoped(Invitation, occasion_id),
        where: i.tenant_id == ^tenant_id and i.id == ^id,
        lock: "FOR UPDATE"
      )
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
      occasion_id: i.occasion_id,
      role: role(i.occasion_id),
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
