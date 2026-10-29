defmodule Ep.Finance.BookConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Ep.Support.AuthHelpers
  alias Ecto.Adapters.SQL.Sandbox
  alias Ep.{Repo, Finance.Books}

  test "simultaneous opposite moves cannot create a hierarchy cycle" do
    {owner, tid, a, b} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = sign_in()

        {:ok, %{result: t}} =
          Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Book race"}, "race-tenant")

        attrs = fn code ->
          %{
            "name" => code,
            "code" => code,
            "base_currency" => "DKK",
            "accounting_authority" => "ep",
            "timezone" => "Europe/Copenhagen",
            "fiscal_year_start_month" => 1
          }
        end

        {:ok, a} = Books.create(owner.principal, t["tenant_id"], attrs.("AA"), "a")
        {:ok, b} = Books.create(owner.principal, t["tenant_id"], attrs.("BB"), "b")
        {owner, t["tenant_id"], a, b}
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(owner, tid) end) end)
    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    barrier = make_ref()

    tasks =
      for {book, target, key} <- [{a, b, "move-a"}, {b, a, "move-b"}] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              ^barrier ->
                Books.revise(
                  owner.principal,
                  tid,
                  book["book_id"],
                  %{
                    "expected_version" => book["stream_version"],
                    "parent_book_id" => target["book_id"]
                  },
                  key
                )
            end
          end)
        end)
      end

    Enum.each(tasks, fn t -> assert_receive {:ready, pid} when pid == t.pid end)
    Enum.each(tasks, fn t -> send(t.pid, barrier) end)
    results = Task.await_many(tasks, 10_000)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :hierarchy_cycle}, &1)) == 1
  end

  defp cleanup(owner, tid) do
    Repo.transaction(fn ->
      ids =
        Repo.all(
          from e in Ep.Events.Event,
            where: e.actor_identity_id == ^owner.principal.identity_id,
            select: e.id
        )

      party_id = Repo.get!(Ep.Auth.Identity, owner.principal.identity_id).party_id
      Repo.delete_all(from j in Oban.Job, where: fragment("?->>'tenant_id'", j.args) == ^tid)
      Repo.delete_all(from v in Ep.Finance.BookView, where: v.tenant_id == ^tid)
      Repo.delete_all(from v in Ep.Projections.Inbox, where: v.tenant_id == ^tid)
      Repo.delete_all(from o in Ep.Events.Outbox, where: o.tenant_id == ^tid)
      Repo.delete_all(from d in Ep.Events.Details, where: d.event_id in ^ids)
      Repo.delete_all(from e in Ep.Events.Event, where: e.id in ^ids)

      Repo.delete_all(
        from h in Ep.Events.StreamHead, where: h.stream_id in ^[tid, owner.principal.identity_id]
      )

      Repo.delete_all(from b in Ep.Finance.Book, where: b.tenant_id == ^tid)
      Repo.delete_all(from d in Ep.Projections.TenantDirectory, where: d.tenant_id == ^tid)
      Repo.delete_all(from c in Ep.Projections.Control, where: c.tenant_id == ^tid)
      Repo.delete_all(from a in Ep.Tenancy.Access, where: a.tenant_id == ^tid)
      Repo.delete_all(from t in Ep.Tenancy.Tenant, where: t.id == ^tid)

      Repo.delete_all(
        from c in Ep.Events.CommandReceipt, where: c.identity_id == ^owner.principal.identity_id
      )

      Repo.delete_all(
        from s in Ep.Auth.Session, where: s.identity_id == ^owner.principal.identity_id
      )

      # The signup challenge belongs only to this synthetic identity's email.
      identity = Repo.get!(Ep.Auth.Identity, owner.principal.identity_id)
      Repo.delete_all(from m in Ep.Auth.MagicLink, where: m.email == ^identity.email)
      Repo.delete!(identity)
      Repo.delete_all(from p in Ep.Auth.Party, where: p.id == ^party_id)
    end)
  end
end
