defmodule Ep.TenantConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Ep.Support.AuthHelpers
  alias Ecto.Adapters.SQL.Sandbox
  alias Ep.Repo
  alias Ep.Auth.{Identity, MagicLink, Party, Session}
  alias Ep.Events.{CommandReceipt, Details, Event, Outbox, StreamHead}
  alias Ep.Projections.{Control, Inbox, TenantDirectory}
  alias Ep.Tenancy.{Access, Tenant}

  test "simultaneous retries on separate database connections accept one tenant" do
    email = "concurrent-#{System.unique_integer([:positive])}@example.test"
    signed = Sandbox.unboxed_run(Repo, fn -> sign_in(email) end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> cleanup(signed.principal.identity_id, email) end)
    end)

    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    barrier = make_ref()

    tasks =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:ready, self()})

          receive do
            {:go, ^barrier} ->
              Sandbox.unboxed_run(Repo, fn ->
                Ep.Tenancy.create_tenant(
                  signed.principal,
                  %{"name" => "Concurrent"},
                  "same-command"
                )
              end)
          end
        end)
      end

    Enum.each(tasks, fn task -> assert_receive {:ready, pid} when pid == task.pid end)
    Enum.each(tasks, fn task -> send(task.pid, {:go, barrier}) end)
    results = Task.await_many(tasks, 15_000)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert results
           |> Enum.map(fn {:ok, result} -> result.result["tenant_id"] end)
           |> Enum.uniq()
           |> length() == 1

    assert Enum.sort(Enum.map(results, fn {:ok, result} -> result.replayed end)) == [false, true]

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(
               from(t in Tenant, where: t.creator_identity_id == ^signed.principal.identity_id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(c in CommandReceipt, where: c.identity_id == ^signed.principal.identity_id),
               :count
             ) == 1
    end)
  end

  # This test commits across independent connections; remove only its own fixture data.
  defp cleanup(identity_id, email) do
    tenant_ids =
      Repo.all(from(t in Tenant, where: t.creator_identity_id == ^identity_id, select: t.id))

    event_ids =
      Repo.all(from(e in Event, where: e.actor_identity_id == ^identity_id, select: e.id))

    identity = Repo.get!(Identity, identity_id)

    Repo.transaction(fn ->
      Repo.delete_all(
        from(j in Oban.Job, where: fragment("?->>'tenant_id'", j.args) in ^tenant_ids)
      )

      Repo.delete_all(from(v in TenantDirectory, where: v.tenant_id in ^tenant_ids))
      Repo.delete_all(from(i in Inbox, where: i.tenant_id in ^tenant_ids))
      Repo.delete_all(from(o in Outbox, where: o.tenant_id in ^tenant_ids))
      Repo.delete_all(from(d in Details, where: d.event_id in ^event_ids))
      Repo.delete_all(from(e in Event, where: e.id in ^event_ids))

      Repo.delete_all(
        from(h in StreamHead, where: h.stream_id in ^tenant_ids or h.stream_id == ^identity_id)
      )

      Repo.delete_all(from(a in Access, where: a.tenant_id in ^tenant_ids))
      Repo.delete_all(from(c in Control, where: c.tenant_id in ^tenant_ids))
      Repo.delete_all(from(c in CommandReceipt, where: c.identity_id == ^identity_id))
      Repo.delete_all(from(t in Tenant, where: t.id in ^tenant_ids))
      Repo.delete_all(from(s in Session, where: s.identity_id == ^identity_id))
      Repo.delete!(identity)
      Repo.delete!(Repo.get!(Party, identity.party_id))
      Repo.delete_all(from(m in MagicLink, where: m.email == ^email))
    end)
  end
end
