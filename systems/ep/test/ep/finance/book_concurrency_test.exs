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

  test "competing account creates with one setup revision accept exactly once" do
    {owner, tid, bid} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = sign_in()

        {:ok, %{result: t}} =
          Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Setup race"}, "tenant")

        tid = t["tenant_id"]

        {:ok, book} =
          Books.create(
            owner.principal,
            tid,
            %{
              "name" => "Race",
              "code" => "RACE",
              "base_currency" => "DKK",
              "accounting_authority" => "ep",
              "timezone" => "Europe/Copenhagen",
              "fiscal_year_start_month" => 1
            },
            "book"
          )

        bid = book["book_id"]

        {:ok, _} =
          Ep.Finance.Setup.command(
            owner.principal,
            tid,
            bid,
            "steward",
            %{
              "identity_id" => owner.principal.identity_id,
              "active" => true,
              "expected_version" => 0
            },
            "grant"
          )

        {owner, tid, bid}
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(owner, tid) end) end)
    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    barrier = make_ref()

    tasks =
      for key <- ["first", "second"] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              ^barrier ->
                Ep.Finance.Setup.command(
                  owner.principal,
                  tid,
                  bid,
                  "account_create",
                  %{
                    "number" => "0010",
                    "name" => key,
                    "kind" => "posting",
                    "expected_version" => 1
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
    assert Enum.count(results, &match?({:error, :version_conflict}, &1)) == 1
  end

  test "competing bindings in different books cannot claim the same occasion" do
    {owner, tid, bids, oid} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = sign_in()

        {:ok, %{result: t}} =
          Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Binding race"}, "tenant")

        tid = t["tenant_id"]

        bids =
          for code <- ["FIRST", "SECOND"] do
            {:ok, b} =
              Books.create(
                owner.principal,
                tid,
                %{
                  "name" => code,
                  "code" => code,
                  "base_currency" => "DKK",
                  "accounting_authority" => "ep",
                  "timezone" => "Europe/Copenhagen",
                  "fiscal_year_start_month" => 1
                },
                code
              )

            {:ok, _} =
              Ep.Finance.Setup.command(
                owner.principal,
                tid,
                b["book_id"],
                "steward",
                %{
                  "identity_id" => owner.principal.identity_id,
                  "active" => true,
                  "expected_version" => 0
                },
                "grant-" <> code
              )

            b["book_id"]
          end

        {:ok, %{result: o}} =
          Ep.Occasions.create(
            owner.principal,
            tid,
            %{"name" => "Camp", "slug" => "camp", "expires_at" => "2031-01-01T00:00:00Z"},
            "occasion"
          )

        {owner, tid, bids, o["occasion_id"]}
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(owner, tid) end) end)
    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    barrier = make_ref()

    tasks =
      for bid <- bids do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              ^barrier ->
                Ep.Finance.Setup.command(
                  owner.principal,
                  tid,
                  bid,
                  "binding",
                  %{"occasion_id" => oid, "active" => true, "expected_version" => 1},
                  bid
                )
            end
          end)
        end)
      end

    Enum.each(tasks, fn t -> assert_receive {:ready, pid} when pid == t.pid end)
    Enum.each(tasks, fn t -> send(t.pid, barrier) end)
    results = Task.await_many(tasks, 10_000)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :binding_taken}, &1)) == 1
  end

  test "the posting-date guard and period closure contend on protected current state" do
    {owner, tid, bid, pid} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = sign_in()

        {:ok, %{result: t}} =
          Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Period lock race"}, "tenant")

        tid = t["tenant_id"]

        {:ok, b} =
          Books.create(
            owner.principal,
            tid,
            %{
              "name" => "Periods",
              "code" => "PERIODS",
              "base_currency" => "DKK",
              "accounting_authority" => "ep",
              "timezone" => "Europe/Copenhagen",
              "fiscal_year_start_month" => 1
            },
            "book"
          )

        bid = b["book_id"]

        {:ok, _} =
          Ep.Finance.Setup.command(
            owner.principal,
            tid,
            bid,
            "steward",
            %{
              "identity_id" => owner.principal.identity_id,
              "active" => true,
              "expected_version" => 0
            },
            "grant"
          )

        {:ok, p} =
          Ep.Finance.Periods.command(
            owner.principal,
            tid,
            bid,
            "create",
            %{
              "name" => "January",
              "start_date" => "2030-01-01",
              "end_date" => "2030-01-31",
              "expected_version" => 0
            },
            "create"
          )

        {:ok, _} =
          Ep.Finance.Periods.command(
            owner.principal,
            tid,
            bid,
            "open",
            %{
              "period_id" => p["period_id"],
              "expected_version" => 1,
              "expected_period_version" => 1
            },
            "open"
          )

        {owner, tid, bid, p["period_id"]}
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(owner, tid) end) end)
    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    release = make_ref()

    guard =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Ep.Finance.Periods.lock_open!(tid, bid, "2030-01-15")
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:guard_held, backend})

            receive do
              ^release -> :guard_completed
            end
          end)
        end)
      end)

    assert_receive {:guard_held, guard_backend}

    closer =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:closing, backend})

          Ep.Finance.Periods.command(
            owner.principal,
            tid,
            bid,
            "close",
            %{"period_id" => pid, "expected_version" => 2, "expected_period_version" => 2},
            "close"
          )
        end)
      end)

    assert_receive {:closing, close_backend}

    assert Sandbox.unboxed_run(Repo, fn ->
             blocked_by?(close_backend, guard_backend, System.monotonic_time(:millisecond) + 5000)
           end)

    send(guard.pid, release)
    assert {:ok, :guard_completed} = Task.await(guard, 10_000)
    assert {:ok, _} = Task.await(closer, 10_000)

    Sandbox.unboxed_run(Repo, fn ->
      assert {:error, :period_not_open} =
               Repo.transaction(fn -> Ep.Finance.Periods.lock_open!(tid, bid, "2030-01-15") end)

      assert {:ok, %{status: "pending", periods: []}} =
               Ep.Finance.Periods.list(owner.principal, tid, bid)
    end)
  end

  defp blocked_by?(waiting, holder, deadline) do
    %{rows: [[blockers]]} = Repo.query!("SELECT pg_blocking_pids($1)", [waiting])

    cond do
      holder in blockers -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> blocked_by?(waiting, holder, deadline)
    end
  end

  defp cleanup(owner, tid) do
    Repo.transaction(fn ->
      ids =
        Repo.all(
          from e in Ep.Events.Event,
            where: e.actor_identity_id == ^owner.principal.identity_id,
            select: e.id
        )

      occasion_ids =
        Repo.all(from o in Ep.Occasions.Occasion, where: o.tenant_id == ^tid, select: o.id)

      book_ids = Repo.all(from b in Ep.Finance.Book, where: b.tenant_id == ^tid, select: b.id)
      party_id = Repo.get!(Ep.Auth.Identity, owner.principal.identity_id).party_id
      Repo.delete_all(from j in Oban.Job, where: fragment("?->>'tenant_id'", j.args) == ^tid)

      for schema <- [
            Ep.Finance.PeriodView,
            Ep.Finance.Period,
            Ep.Finance.PeriodState,
            Ep.Finance.SetupView,
            Ep.Finance.Account,
            Ep.Finance.Binding,
            Ep.Finance.Steward,
            Ep.Finance.SetupState
          ] do
        Repo.delete_all(from r in schema, where: r.tenant_id == ^tid)
      end

      Repo.delete_all(from v in Ep.Finance.BookView, where: v.tenant_id == ^tid)
      Repo.delete_all(from v in Ep.Projections.Inbox, where: v.tenant_id == ^tid)
      Repo.delete_all(from o in Ep.Events.Outbox, where: o.tenant_id == ^tid)
      Repo.delete_all(from d in Ep.Events.Details, where: d.event_id in ^ids)
      Repo.delete_all(from e in Ep.Events.Event, where: e.id in ^ids)

      Repo.delete_all(
        from h in Ep.Events.StreamHead,
          where: h.stream_id in ^([tid, owner.principal.identity_id] ++ book_ids ++ occasion_ids)
      )

      Repo.delete_all(from a in Ep.Occasions.Admin, where: a.tenant_id == ^tid)
      Repo.delete_all(from d in Ep.Occasions.Directory, where: d.tenant_id == ^tid)
      Repo.delete_all(from o in Ep.Occasions.Occasion, where: o.tenant_id == ^tid)
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
