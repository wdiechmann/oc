defmodule Ep.Finance.SetupTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Account, Books, Setup, SetupProjector}

  setup do
    owner = sign_in()
    steward = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Finance setup"}, "tenant")

    tid = t["tenant_id"]

    attrs = %{
      "code" => "SL2030",
      "name" => "SL2030",
      "base_currency" => "DKK",
      "accounting_authority" => "ep",
      "timezone" => "Europe/Copenhagen",
      "fiscal_year_start_month" => 1
    }

    {:ok, b} = Books.create(owner.principal, tid, attrs, "book")

    {:ok, other} =
      Books.create(
        owner.principal,
        tid,
        Map.merge(attrs, %{"code" => "OTHER", "parent_book_id" => b["book_id"]}),
        "other"
      )

    %{
      owner: owner.principal,
      steward: steward.principal,
      tid: tid,
      bid: b["book_id"],
      other: other["book_id"]
    }
  end

  defp cmd(c, actor, action, p, key), do: Setup.command(actor, c.tid, c.bid, action, p, key)

  defp grant(c, active, version),
    do:
      cmd(
        c,
        c.owner,
        "steward",
        %{
          "identity_id" => c.steward.identity_id,
          "active" => active,
          "expected_version" => version
        },
        "grant-#{version}"
      )

  defp account(version, number \\ "0010"),
    do: %{
      "number" => number,
      "name" => "Bank",
      "kind" => "posting",
      "expected_version" => version
    }

  test "tenant administration assigns a steward but cannot configure accounts implicitly", c do
    assert {:error, :not_found} = cmd(c, c.owner, "account_create", account(0), "admin")
    assert {:error, :not_found} = Setup.get(c.steward, c.tid, c.bid)
    assert {:ok, grant_result} = grant(c, true, 0)
    payload = Repo.get!(Ep.Events.Details, hd(grant_result["event_ids"])).payload
    assert payload["change"] == %{"identity_id" => c.steward.identity_id, "active" => true}

    assert {:ok, %{permissions: %{configure: true, assign_stewards: false}}} =
             Setup.get(c.steward, c.tid, c.bid)

    assert {:error, :not_found} = Setup.get(c.steward, c.tid, c.other)

    assert {:error, :not_found} =
             cmd(
               c,
               c.steward,
               "steward",
               %{
                 "identity_id" => c.steward.identity_id,
                 "active" => true,
                 "expected_version" => 1
               },
               "escalate"
             )

    assert {:ok, r} = cmd(c, c.steward, "account_create", account(1), "create")

    assert {:ok, %{"replayed" => true}} =
             cmd(c, c.steward, "account_create", account(1), "create")

    assert {:ok, _} = grant(c, false, 2)
    assert {:error, :not_found} = cmd(c, c.steward, "account_create", account(1), "create")
    assert {:error, :not_found} = Setup.get(c.steward, c.tid, c.bid)
    assert Repo.get!(Account, hd(r["event_ids"])).number == "0010"
  end

  test "stable event IDs, reserved leading-zero numbers and optimistic revisions survive replay",
       c do
    {:ok, _} = grant(c, true, 0)
    {:ok, r} = cmd(c, c.steward, "account_create", account(1), "create")
    id = hd(r["event_ids"])
    assert {:ok, %{status: "pending", accounts: []}} = Setup.get(c.steward, c.tid, c.bid)
    assert {:error, :number_taken} = cmd(c, c.steward, "account_create", account(2), "duplicate")

    assert {:error, :version_conflict} =
             cmd(c, c.steward, "account_create", account(1, "0020"), "stale")

    assert {:error, :idempotency_conflict} =
             cmd(c, c.steward, "account_create", account(1, "0020"), "create")

    revise = %{
      "account_id" => id,
      "number" => "0020",
      "name" => "Cash",
      "kind" => "posting",
      "active" => false,
      "expected_account_version" => 2,
      "expected_version" => 2
    }

    assert {:ok, _} = cmd(c, c.steward, "account_revise", revise, "revise")
    assert {:error, :number_taken} = cmd(c, c.steward, "account_create", account(3), "reserved")
    assert {:ok, 3} = SetupProjector.deliver(c.tid)
    assert {:ok, 0} = SetupProjector.deliver(c.tid)

    assert {:ok,
            %{
              status: "ready",
              accounts: [
                %{
                  "id" => ^id,
                  "number" => "0020",
                  "active" => false,
                  "actor_identity_id" => actor,
                  "application_id" => "internal"
                }
              ]
            }} = Setup.get(c.steward, c.tid, c.bid)

    assert actor == c.steward.identity_id
    events = Repo.aggregate(Ep.Events.Event, :count)
    jobs = Repo.aggregate(Oban.Job, :count)
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    assert Repo.aggregate(Ep.Events.Event, :count) == events
    assert Repo.aggregate(Oban.Job, :count) == jobs
    assert {:ok, %{accounts: [%{"id" => ^id}]}} = Setup.get(c.steward, c.tid, c.bid)
    assert {:ok, _} = Ep.Outbox.requeue_pending()
  end

  test "binding is tenant-local, unique across books and explicitly released before reassignment",
       c do
    {:ok, _} = grant(c, true, 0)

    {:ok, _} =
      Setup.command(
        c.owner,
        c.tid,
        c.other,
        "steward",
        %{"identity_id" => c.steward.identity_id, "active" => true, "expected_version" => 0},
        "other-grant"
      )

    {:ok, %{result: occasion}} =
      Ep.Occasions.create(
        c.owner,
        c.tid,
        %{"name" => "Camp", "slug" => "camp", "expires_at" => "2031-01-01T00:00:00Z"},
        "occasion"
      )

    p = %{"occasion_id" => occasion["occasion_id"], "active" => true, "expected_version" => 1}
    assert {:ok, _} = cmd(c, c.steward, "binding", p, "bind")

    assert {:error, :binding_taken} =
             Setup.command(c.steward, c.tid, c.other, "binding", p, "taken")

    assert {:ok, _} =
             cmd(
               c,
               c.steward,
               "binding",
               %{p | "active" => false, "expected_version" => 2},
               "unbind"
             )

    assert {:ok, _} = Setup.command(c.steward, c.tid, c.other, "binding", p, "move")

    assert {:error, :invalid_setup} =
             cmd(
               c,
               c.steward,
               "binding",
               %{p | "occasion_id" => Ecto.UUID.generate(), "expected_version" => 3},
               "foreign"
             )
  end

  test "occasion administration grants no setup authority; foreign occasions cannot be linked",
       c do
    {:ok, %{result: o}} =
      Ep.Occasions.create(
        c.owner,
        c.tid,
        %{"name" => "Camp", "slug" => "camp", "expires_at" => "2031-01-01T00:00:00Z"},
        "occasion"
      )

    Repo.insert!(%Ep.Occasions.Admin{
      tenant_id: c.tid,
      occasion_id: o["occasion_id"],
      identity_id: c.steward.identity_id
    })

    assert {:error, :not_found} = Setup.get(c.steward, c.tid, c.bid)
    assert {:ok, _} = grant(c, true, 0)
    {:ok, _} = Ep.Finance.BookProjector.deliver(c.tid)
    assert {:ok, %{finance_books: [%{book_id: bid}]}} = Ep.Workspaces.list(c.steward)
    assert bid == c.bid
    stranger = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(stranger.principal, %{"name" => "Foreign"}, "foreign")

    {:ok, %{result: foreign}} =
      Ep.Occasions.create(
        stranger.principal,
        t["tenant_id"],
        %{"name" => "Other camp", "slug" => "camp", "expires_at" => "2031-01-01T00:00:00Z"},
        "foreign-occasion"
      )

    assert {:error, :invalid_setup} =
             cmd(
               c,
               c.steward,
               "binding",
               %{
                 "occasion_id" => foreign["occasion_id"],
                 "active" => true,
                 "expected_version" => 1
               },
               "foreign-binding"
             )

    {:ok, _} = grant(c, false, 1)
    assert {:ok, %{finance_books: []}} = Ep.Workspaces.list(c.steward)
  end

  test "extra fields, invalid inputs and stopped views are safe", c do
    {:ok, _} = grant(c, true, 0)

    for p <- [
          Map.put(account(1), "tenant_id", c.tid),
          %{account(1) | "number" => 10},
          %{account(1) | "kind" => "formula"}
        ] do
      assert {:error, :invalid_setup} =
               cmd(c, c.steward, "account_create", p, Ecto.UUID.generate())
    end

    Repo.update_all(
      from(x in Ep.Projections.Control,
        where: x.tenant_id == ^c.tid and x.name == "finance_setup"
      ),
      set: [state: "stopped"]
    )

    assert {:error, :view_stopped} = Setup.get(c.steward, c.tid, c.bid)
    assert {:error, :view_stopped} = SetupProjector.deliver(c.tid)
  end
end
