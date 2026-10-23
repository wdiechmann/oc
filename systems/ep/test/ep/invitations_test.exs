defmodule Ep.InvitationsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Invitations.Invitation
  alias Ep.Events.{Details, Event}
  alias Ep.Tenancy.Access

  setup do
    owner = sign_in()

    {:ok, %{result: tenant}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "SL"}, "tenant")

    %{owner: owner, tenant_id: tenant["tenant_id"]}
  end

  defp invite(c, email \\ "prospect@example.test", key \\ "invite") do
    Ep.Invitations.invite(c.owner.principal, c.tenant_id, %{"email" => email}, key)
  end

  test "prospect verifies identity then accepts a tenant-bound admin grant, without membership",
       c do
    assert {:ok, %{result: r}} = invite(c, " Prospect@Example.Test ")
    assert r["status"] == "pending"
    assert Repo.aggregate(Access, :count) == 1
    prospect = sign_in("prospect@example.test")
    assert {:ok, %{invitations: [incoming]}} = Ep.Invitations.incoming(prospect.principal)
    assert incoming.tenant_name == "SL" && incoming.invitation_id == r["invitation_id"]
    assert {:error, :not_found} = Ep.Tenancy.get_tenant(prospect.principal, c.tenant_id)

    assert {:ok, %{result: result, replayed: false}} =
             Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "accept")

    assert result["status"] == "accepted" && length(result["event_ids"]) == 2

    assert Repo.get_by!(Access,
             tenant_id: c.tenant_id,
             identity_id: prospect.principal.identity_id
           ).role == "tenant_admin"

    assert Repo.get!(Invitation, r["invitation_id"]).accepted_identity_id ==
             prospect.principal.identity_id

    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :projections)
    assert {:ok, %{source_version: 5}} = Ep.Tenancy.get_tenant(prospect.principal, c.tenant_id)
    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming(prospect.principal)

    assert {:ok, %{replayed: true, result: ^result}} =
             Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "accept")
  end

  test "wrong verified identity, foreign tenant and non-admin invitation operations fail", c do
    {:ok, %{result: r}} = invite(c)
    other = sign_in("other@example.test")
    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming(other.principal)

    assert {:error, :not_found} =
             Ep.Invitations.accept(other.principal, c.tenant_id, r["invitation_id"], "accept")

    assert {:error, :not_found} =
             Ep.Invitations.invite(
               other.principal,
               c.tenant_id,
               %{"email" => "x@example.test"},
               "invite"
             )

    assert {:error, :not_found} =
             Ep.Invitations.revoke(other.principal, c.tenant_id, r["invitation_id"], "revoke")

    assert {:error, :not_found} = Ep.Invitations.list_for_tenant(other.principal, c.tenant_id)
    prospect = sign_in("prospect@example.test")

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               Ecto.UUID.generate(),
               r["invitation_id"],
               "accept"
             )

    assert Repo.aggregate(Access, :count) == 1
  end

  test "revocation is idempotent and prevents acceptance and pending notification", c do
    {:ok, %{result: r}} = invite(c)

    assert {:ok, first} =
             Ep.Invitations.revoke(c.owner.principal, c.tenant_id, r["invitation_id"], "revoke")

    assert {:ok, %{replayed: true, result: result}} =
             Ep.Invitations.revoke(c.owner.principal, c.tenant_id, r["invitation_id"], "revoke")

    assert result == first.result
    prospect = sign_in("prospect@example.test")

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "accept")

    assert :skip = Ep.Invitations.notification(r["invitation_id"])

    assert Repo.aggregate(Access, :count) == 1
  end

  test "expiry and loss of sponsor authority prevent acceptance", c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("prospect@example.test")
    Repo.update_all(Invitation, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "expired")

    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming(prospect.principal)

    assert {:ok, %{invitations: [%{status: "expired"}]}} =
             Ep.Invitations.list_for_tenant(c.owner.principal, c.tenant_id)

    {:ok, %{result: r2}} = invite(c, "prospect@example.test", "replacement")

    Repo.update_all(from(a in Access, where: a.identity_id == ^c.owner.principal.identity_id),
      set: [status: "revoked"]
    )

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tenant_id,
               r2["invitation_id"],
               "sponsor-revoked"
             )

    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming(prospect.principal)
  end

  test "duplicates, command conflicts and invitations to active admins are rejected", c do
    assert {:ok, first} = invite(c)
    assert {:ok, %{result: result, replayed: true}} = invite(c)
    assert result == first.result
    assert {:error, :already_invited} = invite(c, "prospect@example.test", "different")
    assert {:error, :idempotency_conflict} = invite(c, "changed@example.test")
    email = Repo.get!(Ep.Auth.Identity, c.owner.principal.identity_id).email
    assert {:error, :already_admin} = invite(c, email, "self")
    assert {:error, :invalid_email} = invite(c, "bad", "bad")
    assert {:error, :invalid_idempotency_key} = invite(c, "valid@example.test", nil)
    assert Repo.aggregate(Invitation, :count) == 1
  end

  test "accepted invitation cannot be revoked or used to restore later revoked authority", c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("prospect@example.test")

    {:ok, _} =
      Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "accept")

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.revoke(c.owner.principal, c.tenant_id, r["invitation_id"], "revoke")

    Repo.update_all(from(a in Access, where: a.identity_id == ^prospect.principal.identity_id),
      set: [status: "revoked"]
    )

    assert {:ok, %{replayed: true}} =
             Ep.Invitations.accept(prospect.principal, c.tenant_id, r["invitation_id"], "accept")

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tenant_id,
               r["invitation_id"],
               "new-accept"
             )

    assert Repo.get_by!(Access, identity_id: prospect.principal.identity_id).status == "revoked"
  end

  test "transaction rollback removes invitation, facts and notification; events contain no email",
       c do
    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _} = invite(c)
               Repo.rollback(:abort)
             end)

    assert Repo.aggregate(Invitation, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 1
    {:ok, %{result: r}} = invite(c)
    event = Repo.get!(Event, hd(r["event_ids"]))
    payload = Repo.get!(Details, event.id).payload
    refute Map.has_key?(payload, "email")
    assert event.actor_identity_id == c.owner.principal.identity_id
    assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
  end
end
