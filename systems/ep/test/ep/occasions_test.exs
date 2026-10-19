defmodule Ep.OccasionsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Occasions.{Admin, Directory, Occasion}
  alias Ep.Events.{Event, Outbox}
  alias Ep.Projections.{Control, OccasionDirectoryProjector}

  setup do
    signed = sign_in()

    {:ok, %{result: tenant}} =
      Ep.Tenancy.create_tenant(signed.principal, %{"name" => "SL"}, "tenant")

    %{signed: signed, tenant_id: tenant["tenant_id"]}
  end

  defp params(slug \\ "sl2030"),
    do: %{
      "name" => "SL2030",
      "slug" => slug,
      "expires_at" => "2031-01-01T00:00:00Z",
      "assign_self_as_admin" => true
    }

  test "creation commits scoped facts, guard, optional admin, receipt and projection wakeup", c do
    assert {:ok, %{result: r, replayed: false}} =
             Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "first")

    assert r["stream_version"] == 2
    row = Repo.get!(Occasion, r["occasion_id"])
    assert row.tenant_id == c.tenant_id
    assert row.status == "draft" && row.recruitment_state == "closed"
    assert Repo.get_by!(Admin, occasion_id: row.id).identity_id == c.signed.principal.identity_id

    events =
      Repo.all(from(e in Event, where: e.occasion_id == ^row.id, order_by: e.stream_version))

    assert Enum.map(events, & &1.event_type) == ["OccasionCreated", "OccasionAdminGranted"]

    assert Enum.all?(
             events,
             &(&1.scope == "occasion" && &1.tenant_id == c.tenant_id &&
                 &1.actor_identity_id == c.signed.principal.identity_id)
           )

    assert {:ok, %{status: :pending}} = Ep.Occasions.get(c.signed.principal, c.tenant_id, row.id)
    assert %{failure: 0, success: 2} = Oban.drain_queue(queue: :projections)

    assert {:ok,
            %{name: "SL2030", lifecycle: "draft", recruitment_state: "closed", source_version: 2}} =
             Ep.Occasions.get(c.signed.principal, c.tenant_id, row.id)

    assert {:ok, 0} = OccasionDirectoryProjector.deliver(c.tenant_id)
    assert Repo.aggregate(Directory, :count) == 1

    assert {:ok, %{status: :ready, occasions: [_]}} =
             Ep.Occasions.list(c.signed.principal, c.tenant_id)
  end

  test "retry is stable and changed payload or parent conflicts", c do
    assert {:ok, first} = Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "same")
    assert {:ok, retry} = Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "same")
    assert retry.replayed && retry.result == first.result

    assert {:error, :idempotency_conflict} =
             Ep.Occasions.create(c.signed.principal, c.tenant_id, params("changed"), "same")

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(c.signed.principal, %{"name" => "Other"}, "other")

    assert {:error, :idempotency_conflict} =
             Ep.Occasions.create(c.signed.principal, t["tenant_id"], params(), "same")

    assert Repo.aggregate(Occasion, :count) == 1
  end

  test "slug uniqueness is tenant-local and admin assignment is optional", c do
    Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "one")

    assert {:error, :slug_taken} =
             Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "two")

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(c.signed.principal, %{"name" => "Other"}, "other")

    p = Map.put(params(), "assign_self_as_admin", false)

    assert {:ok, %{result: r}} =
             Ep.Occasions.create(c.signed.principal, t["tenant_id"], p, "three")

    assert r["stream_version"] == 1
    refute Repo.get_by(Admin, occasion_id: r["occasion_id"])
  end

  test "foreign, revoked and retired tenant access cannot create or enumerate occasions", c do
    other = sign_in()

    assert {:error, :not_found} =
             Ep.Occasions.create(other.principal, c.tenant_id, params(), "foreign")

    assert {:error, :not_found} = Ep.Occasions.list(other.principal, c.tenant_id)

    Repo.update_all(from(a in Ep.Tenancy.Access, where: a.tenant_id == ^c.tenant_id),
      set: [status: "revoked"]
    )

    assert {:error, :not_found} =
             Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "revoked")

    Repo.update_all(from(a in Ep.Tenancy.Access, where: a.tenant_id == ^c.tenant_id),
      set: [status: "active"]
    )

    Repo.update_all(from(t in Ep.Tenancy.Tenant, where: t.id == ^c.tenant_id),
      set: [status: "retired"]
    )

    assert {:error, :not_found} =
             Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "retired")

    assert Repo.aggregate(Occasion, :count) == 0
  end

  test "occasion administrator has only the granted occasion, never tenant-level creation", c do
    {:ok, %{result: one}} = Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "one")

    {:ok, %{result: two}} =
      Ep.Occasions.create(c.signed.principal, c.tenant_id, params("sibling"), "two")

    other = sign_in()

    Repo.insert!(%Admin{
      tenant_id: c.tenant_id,
      occasion_id: one["occasion_id"],
      identity_id: other.principal.identity_id
    })

    OccasionDirectoryProjector.deliver(c.tenant_id)

    assert {:ok, %{status: :ready}} =
             Ep.Occasions.get(other.principal, c.tenant_id, one["occasion_id"])

    assert {:error, :not_found} =
             Ep.Occasions.get(other.principal, c.tenant_id, two["occasion_id"])

    assert {:error, :not_found} =
             Ep.Occasions.create(other.principal, c.tenant_id, params("third"), "three")

    assert {:error, :not_found} = Ep.Occasions.list(other.principal, c.tenant_id)
  end

  test "invalid fields and outer rollback leave no occasion acceptance", c do
    for {field, value, error} <- [
          {"name", " ", :invalid_name},
          {"slug", "SL/2030", :invalid_slug},
          {"expires_at", "2020-01-01T00:00:00Z", :invalid_expiry},
          {"assign_self_as_admin", "true", :invalid_admin_option}
        ] do
      assert {:error, ^error} =
               Ep.Occasions.create(
                 c.signed.principal,
                 c.tenant_id,
                 Map.put(params(), field, value),
                 "invalid"
               )
    end

    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "rollback")

               Repo.rollback(:abort)
             end)

    assert Repo.aggregate(Occasion, :count) == 0
    assert Repo.aggregate(Admin, :count) == 0
    assert Repo.aggregate(from(e in Event, where: e.scope == "occasion"), :count) == 0
  end

  test "stopped occasion projection does not stop tenant projection or serve stale values", c do
    {:ok, %{result: r}} = Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "one")

    Repo.update_all(
      from(v in Control, where: v.tenant_id == ^c.tenant_id and v.name == "occasion_directory"),
      set: [state: "stopped"]
    )

    assert {:ok, 2} = Ep.Projections.TenantDirectoryProjector.deliver(c.tenant_id)
    assert {:error, :view_stopped} = OccasionDirectoryProjector.deliver(c.tenant_id)

    assert {:error, :view_stopped} =
             Ep.Occasions.get(c.signed.principal, c.tenant_id, r["occasion_id"])

    assert {:error, :view_stopped} = Ep.Occasions.list(c.signed.principal, c.tenant_id)
    assert Repo.aggregate(Directory, :count) == 0
  end

  test "unsupported projection rolls back and lost jobs are recoverable", c do
    {:ok, %{result: r}} = Ep.Occasions.create(c.signed.principal, c.tenant_id, params(), "one")
    [_, event_id] = r["event_ids"]
    Repo.update_all(from(e in Event, where: e.id == ^event_id), set: [schema_version: 99])
    assert_raise RuntimeError, fn -> OccasionDirectoryProjector.deliver(c.tenant_id) end
    assert Repo.aggregate(Directory, :count) == 0
    Repo.update_all(from(e in Event, where: e.id == ^event_id), set: [schema_version: 1])
    Repo.delete_all(Oban.Job)
    assert {:ok, 1} = Ep.Outbox.requeue_pending()
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :projections)
    assert Repo.aggregate(from(o in Outbox, where: is_nil(o.delivered_at)), :count) == 0
  end
end
