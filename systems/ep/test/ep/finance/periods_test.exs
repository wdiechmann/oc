defmodule Ep.Finance.PeriodsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, Period, Periods, PeriodProjector, Setup}

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Periods"}, "tenant")

    tid = t["tenant_id"]

    attrs = %{
      "code" => "PERIODS",
      "name" => "Periods",
      "base_currency" => "DKK",
      "accounting_authority" => "ep",
      "timezone" => "Europe/Copenhagen",
      "fiscal_year_start_month" => 1
    }

    {:ok, b} = Books.create(owner.principal, tid, attrs, "book")
    %{actor: owner.principal, tid: tid, bid: b["book_id"], attrs: attrs}
  end

  defp grant(c),
    do:
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => true, "expected_version" => 0},
        "steward"
      )

  defp authority(c, allow, version),
    do:
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "reopening_authority",
        %{"identity_id" => c.actor.identity_id, "allow" => allow, "expected_version" => version},
        "reopen-#{version}"
      )

  defp attrs(version, first \\ "2030-01-01", last \\ "2030-01-31"),
    do: %{
      "name" => "January 2030",
      "start_date" => first,
      "end_date" => last,
      "expected_version" => version
    }

  defp cmd(c, action, params, key \\ nil),
    do: Periods.command(c.actor, c.tid, c.bid, action, params, key || Ecto.UUID.generate())

  defp transition(pid, version, period_version),
    do: %{
      "period_id" => pid,
      "expected_version" => version,
      "expected_period_version" => period_version
    }

  test "periods require explicit setup authority and replay never bypasses revocation", c do
    assert {:ok, %{permissions: %{configure: false, reopen: false}, periods: []}} =
             Periods.list(c.actor, c.tid, c.bid)

    assert {:error, :not_found} = cmd(c, "create", attrs(0))
    {:ok, _} = grant(c)
    assert {:ok, result} = cmd(c, "create", attrs(0), "create")
    assert result["period_id"] == hd(result["event_ids"])
    assert {:ok, %{"replayed" => true}} = cmd(c, "create", attrs(0), "create")

    assert {:error, :idempotency_conflict} =
             cmd(c, "create", Map.put(attrs(0), "name", "Other"), "create")

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => false, "expected_version" => 1},
        "revoke"
      )

    assert {:error, :not_found} = cmd(c, "create", attrs(0), "create")

    assert {:ok, %{permissions: %{configure: false, reopen: false}}} =
             Periods.list(c.actor, c.tid, c.bid)

    stranger = sign_in()
    assert {:error, :not_found} = Periods.list(stranger.principal, c.tid, c.bid)
    assert {:error, :not_found} = Periods.list(c.actor, c.tid, "bad-id")
  end

  test "dates are inclusive and nonoverlapping within each book, with strict date and field validation",
       c do
    {:ok, _} = grant(c)
    {:ok, _} = cmd(c, "create", attrs(0))
    assert {:error, :period_overlap} = cmd(c, "create", attrs(1, "2030-01-31", "2030-02-28"))
    assert {:ok, _} = cmd(c, "create", attrs(1, "2030-02-01", "2030-02-28"))

    for p <- [
          attrs(2, "2030-02-30", "2030-03-31"),
          attrs(2, "2030-04-01", "2030-03-31"),
          attrs(2, "2030-03-01T00:00:00Z", "2030-03-31"),
          attrs(2, "0000-01-01", "0000-01-31"),
          Map.put(attrs(2), "occasion_id", Ecto.UUID.generate())
        ] do
      assert {:error, :invalid_period} = cmd(c, "create", p)
    end

    {:ok, b} = Books.create(c.actor, c.tid, %{c.attrs | "code" => "OTHER"}, "other")

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        b["book_id"],
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => true, "expected_version" => 0},
        "other-steward"
      )

    assert {:ok, _} =
             Periods.command(c.actor, c.tid, b["book_id"], "create", attrs(0), "other-period")
  end

  test "draft corrections, lifecycle, reopening permission and full audit history survive replay",
       c do
    {:ok, _} = grant(c)
    {:ok, r} = cmd(c, "create", attrs(0))
    pid = r["period_id"]

    revision =
      Map.merge(attrs(1), %{
        "period_id" => pid,
        "expected_period_version" => 1,
        "name" => "January"
      })

    assert {:ok, _} = cmd(c, "revise", revision)
    assert {:error, :version_conflict} = cmd(c, "open", transition(pid, 1, 1))
    assert {:ok, _} = cmd(c, "open", transition(pid, 2, 2))

    assert {:error, :invalid_transition} =
             cmd(c, "revise", %{
               revision
               | "expected_version" => 3,
                 "expected_period_version" => 3
             })

    assert {:ok, _} = Repo.transaction(fn -> Periods.lock_open!(c.tid, c.bid, "2030-01-01") end)
    assert {:ok, _} = Repo.transaction(fn -> Periods.lock_open!(c.tid, c.bid, "2030-01-31") end)

    assert {:error, :period_not_open} =
             Repo.transaction(fn -> Periods.lock_open!(c.tid, c.bid, "2030-02-01") end)

    assert {:ok, _} = cmd(c, "close", transition(pid, 3, 3))

    assert {:error, :period_not_open} =
             Repo.transaction(fn -> Periods.lock_open!(c.tid, c.bid, "2030-01-15") end)

    reopen = Map.put(transition(pid, 4, 4), "reason", "Reviewed correction")
    assert {:error, :not_found} = cmd(c, "reopen", reopen)
    {:ok, _} = authority(c, true, 1)
    assert {:error, :invalid_reason} = cmd(c, "reopen", %{reopen | "reason" => "  "})
    assert {:ok, _} = cmd(c, "reopen", reopen, "reopen")
    assert Repo.get!(Period, pid).status == "open"
    assert {:ok, %{status: "pending", periods: []}} = Periods.list(c.actor, c.tid, c.bid)
    assert {:ok, 5} = PeriodProjector.deliver(c.tid)
    assert {:ok, 0} = PeriodProjector.deliver(c.tid)
    assert {:ok, data} = Periods.list(c.actor, c.tid, c.bid)
    [period] = data.periods

    assert Enum.map(period["history"], & &1["event_type"]) ==
             ~w(PeriodCreated PeriodRevised PeriodOpened PeriodClosed PeriodReopened)

    assert List.last(period["history"])["reason"] == "Reviewed correction"
    assert List.last(period["history"])["actor_identity_id"] == c.actor.identity_id
    assert List.last(period["history"])["application_id"] == "internal"
    events = Repo.aggregate(Ep.Events.Event, :count)
    jobs = Repo.aggregate(Oban.Job, :count)
    assert {:ok, :ok} = PeriodProjector.rebuild(c.tid)
    assert Repo.aggregate(Ep.Events.Event, :count) == events
    assert Repo.aggregate(Oban.Job, :count) == jobs
    assert {:ok, %{periods: [^period]}} = Periods.list(c.actor, c.tid, c.bid)
    {:ok, _} = authority(c, false, 2)
    assert {:error, :not_found} = cmd(c, "reopen", reopen, "reopen")
  end

  test "reopening authority is separate, book-local and cleared by steward revocation", c do
    assert {:error, :not_found} = authority(c, true, 0)
    {:ok, _} = grant(c)
    assert {:ok, _} = authority(c, true, 1)
    assert {:ok, %{permissions: %{reopen: true}}} = Periods.list(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => false, "expected_version" => 2},
        "revoke"
      )

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => true, "expected_version" => 3},
        "reassign"
      )

    assert {:ok, %{permissions: %{configure: true, reopen: false}}} =
             Periods.list(c.actor, c.tid, c.bid)
  end

  test "stopped serving never supplies stale period success; recovery requeues the proper worker",
       c do
    {:ok, _} = grant(c)
    {:ok, r} = cmd(c, "create", attrs(0))
    {:ok, _} = cmd(c, "open", transition(r["period_id"], 1, 1))
    {:ok, _} = Ep.Outbox.requeue_pending()
    assert Repo.exists?(from j in Oban.Job, where: j.worker == "Ep.Finance.PeriodWorker")

    Repo.update_all(
      from(x in Ep.Projections.Control,
        where: x.tenant_id == ^c.tid and x.name == "finance_periods"
      ),
      set: [state: "stopped"]
    )

    assert {:error, :view_stopped} = Periods.list(c.actor, c.tid, c.bid)
    assert {:error, :view_stopped} = PeriodProjector.deliver(c.tid)
    assert {:ok, _} = Repo.transaction(fn -> Periods.lock_open!(c.tid, c.bid, "2030-01-15") end)
  end
end
