defmodule Ep.OccasionInvitationsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Invitations.Invitation
  alias Ep.Occasions.Admin

  setup do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "SL"}, "tenant")

    occasions =
      for slug <- ["sl2026", "sl2030"] do
        {:ok, %{result: r}} =
          Ep.Occasions.create(
            owner.principal,
            t["tenant_id"],
            %{"name" => slug, "slug" => slug, "expires_at" => "2032-01-01T00:00:00Z"},
            slug
          )

        r["occasion_id"]
      end

    [one, two] = occasions
    %{owner: owner, tid: t["tenant_id"], oid: one, sibling: two}
  end

  defp invite(c, email \\ "occasion-prospect@example.test", key \\ "invite", oid \\ nil) do
    Ep.Invitations.invite(c.owner.principal, c.tid, %{"email" => email}, key, oid || c.oid)
  end

  test "accepted grant is restricted to the occasion, with no tenant access or membership", c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("occasion-prospect@example.test")

    assert {:ok, %{invitations: [%{role: "occasion_admin", occasion_id: oid, status: "pending"}]}} =
             Ep.Invitations.incoming_occasions(prospect.principal)

    assert oid == c.oid
    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming(prospect.principal)

    assert {:ok, %{result: accepted}} =
             Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "accept", c.oid)

    assert accepted["occasion_id"] == c.oid

    assert Repo.get_by!(Admin, tenant_id: c.tid, occasion_id: c.oid).identity_id ==
             prospect.principal.identity_id

    refute Repo.get_by(Ep.Tenancy.Access, identity_id: prospect.principal.identity_id)
    assert %{failure: 0} = Oban.drain_queue(queue: :projections)

    assert {:ok, %{name: "sl2026", source_version: 4, can_manage_admins: false}} =
             Ep.Occasions.get(prospect.principal, c.tid, c.oid)

    assert {:error, :not_found} = Ep.Tenancy.get_tenant(prospect.principal, c.tid)
    assert {:error, :not_found} = Ep.Occasions.get(prospect.principal, c.tid, c.sibling)

    assert {:error, :not_found} =
             Ep.Invitations.invite(
               prospect.principal,
               c.tid,
               %{"email" => "other@example.test"},
               "delegate",
               c.oid
             )

    assert {:ok, %{invitations: [%{status: "accepted"}]}} =
             Ep.Invitations.incoming_occasions(prospect.principal)

    events =
      Repo.all(
        from(e in Ep.Events.Event, where: e.occasion_id == ^c.oid, order_by: e.stream_version)
      )

    assert Enum.map(events, & &1.event_type) == [
             "OccasionCreated",
             "OccasionAdminInvitationCreated",
             "OccasionAdminInvitationAccepted",
             "OccasionAdminGranted"
           ]

    assert Enum.all?(events, &(&1.scope == "occasion" && &1.tenant_id == c.tid))

    assert {:ok, %{replayed: true, result: ^accepted}} =
             Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "accept", c.oid)
  end

  test "tenant endpoint, sibling scope, foreign tenant and wrong email cannot accept", c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("occasion-prospect@example.test")
    wrong = sign_in()

    assert {:error, :not_found} =
             Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "tenant")

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tid,
               r["invitation_id"],
               "sibling",
               c.sibling
             )

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               Ecto.UUID.generate(),
               r["invitation_id"],
               "foreign",
               c.oid
             )

    assert {:error, :not_found} =
             Ep.Invitations.accept(wrong.principal, c.tid, r["invitation_id"], "wrong", c.oid)

    assert {:error, :not_found} =
             Ep.Invitations.revoke(c.owner.principal, c.tid, r["invitation_id"], "tenant-revoke")

    assert {:ok, %{invitations: []}} = Ep.Invitations.list_for_tenant(c.owner.principal, c.tid)
    assert Repo.aggregate(Admin, :count) == 0
  end

  test "same recipient can be invited independently at tenant and sibling occasion scopes", c do
    {:ok, first} = invite(c)
    assert {:ok, %{replayed: true, result: result}} = invite(c)
    assert result == first.result
    assert {:error, :already_invited} = invite(c, "occasion-prospect@example.test", "duplicate")

    assert {:error, :idempotency_conflict} =
             invite(c, "occasion-prospect@example.test", "invite", c.sibling)

    assert {:ok, _} = invite(c, "occasion-prospect@example.test", "sibling", c.sibling)

    assert {:ok, _} =
             Ep.Invitations.invite(
               c.owner.principal,
               c.tid,
               %{"email" => "occasion-prospect@example.test"},
               "tenant"
             )

    assert {:ok, %{invitations: [_]}} =
             Ep.Invitations.list_for_tenant(c.owner.principal, c.tid, c.oid)

    assert {:ok, %{invitations: [_]}} = Ep.Invitations.list_for_tenant(c.owner.principal, c.tid)
  end

  test "revoked and expired invitations cannot grant access or send a notification", c do
    {:ok, %{result: r}} = invite(c)

    assert {:ok, _} =
             Ep.Invitations.revoke(c.owner.principal, c.tid, r["invitation_id"], "revoke", c.oid)

    prospect = sign_in("occasion-prospect@example.test")

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "accept", c.oid)

    assert :skip = Ep.Invitations.notification(r["invitation_id"])
    {:ok, %{result: newer}} = invite(c, "occasion-prospect@example.test", "replacement")

    Repo.update_all(from(i in Invitation, where: i.id == ^newer["invitation_id"]),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tid,
               newer["invitation_id"],
               "expired",
               c.oid
             )

    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming_occasions(prospect.principal)
    assert Repo.aggregate(Admin, :count) == 0
  end

  test "retirement and loss of sponsor authority block pending invitations", c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("occasion-prospect@example.test")

    Repo.update_all(from(o in Ep.Occasions.Occasion, where: o.id == ^c.oid),
      set: [status: "retired"]
    )

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tid,
               r["invitation_id"],
               "retired",
               c.oid
             )

    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming_occasions(prospect.principal)
    assert :skip = Ep.Invitations.notification(r["invitation_id"])

    Repo.update_all(from(o in Ep.Occasions.Occasion, where: o.id == ^c.oid),
      set: [status: "draft"]
    )

    Repo.update_all(from(a in Ep.Tenancy.Access, where: a.tenant_id == ^c.tid),
      set: [status: "revoked"]
    )

    assert {:error, :not_found} =
             Ep.Invitations.accept(
               prospect.principal,
               c.tid,
               r["invitation_id"],
               "sponsor",
               c.oid
             )

    assert :skip = Ep.Invitations.notification(r["invitation_id"])
  end

  test "accepted navigation depends on current grant and retries never resurrect revoked grants",
       c do
    {:ok, %{result: r}} = invite(c)
    prospect = sign_in("occasion-prospect@example.test")
    Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "accept", c.oid)
    Repo.update_all(from(a in Admin, where: a.occasion_id == ^c.oid), set: [status: "revoked"])
    assert {:ok, %{invitations: []}} = Ep.Invitations.incoming_occasions(prospect.principal)

    assert {:ok, %{replayed: true}} =
             Ep.Invitations.accept(prospect.principal, c.tid, r["invitation_id"], "accept", c.oid)

    assert Repo.get_by!(Admin, occasion_id: c.oid).status == "revoked"

    assert {:error, :invitation_unavailable} =
             Ep.Invitations.revoke(c.owner.principal, c.tid, r["invitation_id"], "revoke", c.oid)
  end

  test "notification identifies exact occasion and rollback removes acceptance components", c do
    assert {:error, :abort} =
             Repo.transaction(fn ->
               {:ok, _} = invite(c)
               Repo.rollback(:abort)
             end)

    assert Repo.aggregate(Invitation, :count) == 0
    {:ok, %{result: r}} = invite(c)

    assert {:ok, %{occasion_id: oid, occasion_name: "sl2026", role: "occasion_admin"}} =
             Ep.Invitations.notification(r["invitation_id"])

    assert oid == c.oid
  end
end
