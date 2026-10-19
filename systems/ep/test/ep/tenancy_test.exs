defmodule Ep.TenancyTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Events.{CommandReceipt, Details, Event, Outbox, StreamHead}
  alias Ep.Projections.{Control, Inbox, TenantDirectory, TenantDirectoryProjector, TenantWorker}
  alias Ep.Tenancy.{Access, Tenant}

  setup do
    %{signed: sign_in()}
  end

  test "acceptance atomically persists tenant, first admin, events, receipt, outbox and job", %{
    signed: s
  } do
    assert {:ok, %{result: result, replayed: false}} =
             Ep.Tenancy.create_tenant(s.principal, %{"name" => "SL"}, "create-1")

    id = result["tenant_id"]
    assert Repo.get!(Tenant, id).creator_identity_id == s.principal.identity_id
    assert Repo.get_by!(Access, tenant_id: id).role == "tenant_admin"
    assert Repo.aggregate(CommandReceipt, :count) == 1
    assert Repo.aggregate(Outbox, :count) == 2
    assert Repo.aggregate(Oban.Job, :count) == 1
    events = Repo.all(from(e in Event, where: e.tenant_id == ^id, order_by: e.stream_version))
    assert Enum.map(events, & &1.event_type) == ["TenantCreated", "TenantAdminGranted"]
    assert Enum.map(events, & &1.stream_version) == [1, 2]

    assert Enum.all?(
             events,
             &(&1.actor_identity_id == s.principal.identity_id and is_nil(&1.occasion_id))
           )

    assert Enum.map(events, & &1.id) == result["event_ids"]
    assert Repo.get_by!(StreamHead, stream_id: id).version == 2
    assert {:ok, %{status: :pending}} = Ep.Tenancy.get_tenant(s.principal, id)
    assert Repo.aggregate(TenantDirectory, :count) == 0
  end

  test "idempotent retry returns original result; changed request conflicts", %{signed: s} do
    assert {:ok, first} = Ep.Tenancy.create_tenant(s.principal, %{"name" => "SL"}, "same-key")
    assert {:ok, retry} = Ep.Tenancy.create_tenant(s.principal, %{"name" => "SL"}, "same-key")
    assert retry.replayed
    assert retry.result == first.result

    assert {:error, :idempotency_conflict} =
             Ep.Tenancy.create_tenant(s.principal, %{"name" => "Changed"}, "same-key")

    assert Repo.aggregate(Tenant, :count) == 1
    assert Repo.aggregate(Outbox, :count) == 2
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "invalid payload or absent key creates no partial acceptance", %{signed: s} do
    assert {:error, :invalid_name} =
             Ep.Tenancy.create_tenant(s.principal, %{"name" => " "}, "key")

    assert {:error, :invalid_idempotency_key} =
             Ep.Tenancy.create_tenant(s.principal, %{"name" => "SL"}, nil)

    assert Repo.aggregate(Tenant, :count) == 0
    assert Repo.aggregate(CommandReceipt, :count) == 0
  end

  test "outer transaction failure rolls back every accepted component", %{signed: s} do
    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        Ep.Tenancy.create_tenant(s.principal, %{"name" => "Rollback"}, "rollback")

               Repo.rollback(:abort)
             end)

    assert Repo.aggregate(Tenant, :count) == 0
    assert Repo.aggregate(Access, :count) == 0
    assert Repo.aggregate(Outbox, :count) == 0
    assert Repo.aggregate(CommandReceipt, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
    assert Repo.aggregate(from(e in Event, where: e.scope == "tenant"), :count) == 0
  end

  test "durable worker projects and acknowledges both events once", %{signed: s} do
    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(s.principal, %{"name" => "Projected"}, "project")

    id = result["tenant_id"]
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :projections)

    assert {:ok, %{status: :ready, name: "Projected", source_version: 2}} =
             Ep.Tenancy.get_tenant(s.principal, id)

    assert Repo.aggregate(Inbox, :count) == 2
    assert Repo.aggregate(from(o in Outbox, where: is_nil(o.delivered_at)), :count) == 0
    assert :ok = TenantWorker.perform(%Oban.Job{args: %{"tenant_id" => id}})
    assert Repo.aggregate(Inbox, :count) == 2
    assert Repo.aggregate(TenantDirectory, :count) == 1
  end

  test "failed projection rolls back inbox, output and acknowledgement and can retry", %{
    signed: s
  } do
    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(s.principal, %{"name" => "Recover"}, "recover")

    [_, second] = result["event_ids"]
    event = Repo.get!(Event, second)
    Repo.update!(Ecto.Changeset.change(event, schema_version: 99))

    assert_raise RuntimeError, "unsupported tenant event or schema version", fn ->
      TenantDirectoryProjector.deliver(result["tenant_id"])
    end

    assert Repo.aggregate(TenantDirectory, :count) == 0
    assert Repo.aggregate(Inbox, :count) == 0
    assert Repo.aggregate(from(o in Outbox, where: is_nil(o.delivered_at)), :count) == 2
    Repo.update_all(from(e in Event, where: e.id == ^event.id), set: [schema_version: 1])
    assert {:ok, 2} = TenantDirectoryProjector.deliver(result["tenant_id"])
  end

  test "pending committed outbox work can be requeued after job loss", %{signed: s} do
    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(s.principal, %{"name" => "Lost job"}, "lost")

    Repo.delete_all(Oban.Job)
    assert {:ok, 1} = Ep.Outbox.requeue_pending()
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :projections)
    assert {:ok, %{status: :ready}} = Ep.Tenancy.get_tenant(s.principal, result["tenant_id"])
    assert {:ok, 0} = Ep.Outbox.requeue_pending()
  end

  test "projection rebuild has no new events or external jobs", %{signed: s} do
    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(s.principal, %{"name" => "Replay"}, "replay")

    id = result["tenant_id"]
    assert {:ok, 2} = TenantDirectoryProjector.deliver(id)
    expected = Repo.get_by!(TenantDirectory, tenant_id: id)
    assert {:ok, :ok} = TenantDirectoryProjector.rebuild(id)
    actual = Repo.get_by!(TenantDirectory, tenant_id: id)

    assert {actual.name, actual.source_version, actual.last_event_id} ==
             {expected.name, expected.source_version, expected.last_event_id}

    assert Repo.aggregate(Oban.Job, :count) == 1
    assert Repo.aggregate(from(e in Event, where: e.tenant_id == ^id), :count) == 2
  end

  test "current access and stopped control override existing MV content", %{signed: s} do
    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(s.principal, %{"name" => "Private"}, "private")

    id = result["tenant_id"]
    TenantDirectoryProjector.deliver(id)
    other = sign_in()
    assert {:error, :not_found} = Ep.Tenancy.get_tenant(other.principal, id)
    assert {:error, :not_found} = Ep.Tenancy.get_tenant(other.principal, Ecto.UUID.generate())
    Repo.update_all(from(c in Control, where: c.tenant_id == ^id), set: [state: "stopped"])
    assert {:error, :view_stopped} = Ep.Tenancy.get_tenant(s.principal, id)
    assert {:error, :view_stopped} = TenantDirectoryProjector.deliver(id)
    Repo.update_all(from(c in Control, where: c.tenant_id == ^id), set: [state: "running"])
    Repo.update_all(from(a in Access, where: a.tenant_id == ^id), set: [status: "revoked"])
    assert {:error, :not_found} = Ep.Tenancy.get_tenant(s.principal, id)
    assert Repo.aggregate(Details, :count) == 4
  end
end
