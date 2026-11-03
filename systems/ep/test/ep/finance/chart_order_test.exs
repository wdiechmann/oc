defmodule Ep.Finance.ChartOrderTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Account, Books, ChartImport, ChartImports, ChartOrder, Setup, SetupProjector}

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Ordering"}, "tenant")

    tid = t["tenant_id"]

    {:ok, book} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "Order",
          "code" => "ORDER",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = book["book_id"]

    {:ok, _} =
      Setup.command(
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

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "initialize"
      )

    {:ok, _} = SetupProjector.deliver(tid)

    {:ok, upload} =
      ChartImports.upload(owner.principal, tid, bid, %{
        "headers" => ~w(type number name position formula),
        "records" => [
          ["posting", "0010", "Bank", "10", ""],
          ["header", "", "Header", "20", ""],
          ["calculation", "", "Total", "30", "[0010] * 2"]
        ]
      })

    {:ok, preview} =
      ChartImports.preview(owner.principal, tid, bid, upload.import_id, %{
        "mapping" => upload.mapping
      })

    {:ok, _} =
      ChartImports.accept(
        owner.principal,
        tid,
        bid,
        upload.import_id,
        %{"digest" => preview.digest, "expected_version" => preview.expected_version},
        "seed"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    %{actor: owner.principal, token: owner.token, tid: tid, bid: bid, csv_review: preview}
  end

  defp preview(c, ids) do
    {:ok, data} = ChartOrder.get(c.actor, c.tid, c.bid)

    {:ok, review} =
      ChartOrder.preview(c.actor, c.tid, c.bid, %{
        "ordered_ids" => ids,
        "expected_version" => data.source_version
      })

    review
  end

  defp accept(c, review, key \\ "order"),
    do:
      ChartOrder.accept(
        c.actor,
        c.tid,
        c.bid,
        review.review_id,
        %{"digest" => review.digest, "expected_version" => review.expected_version},
        key
      )

  defp accounts(c),
    do:
      Repo.all(
        from a in Account, where: a.book_id == ^c.bid and not a.retired, order_by: a.position
      )

  test "full-chart moves/rebalance are position-only, atomic and replayable", c do
    before = accounts(c)
    ids = Enum.reverse(Enum.map(before, & &1.id))
    review = preview(c, ids)
    assert review.plan["changed_count"] == 3
    assert Enum.map(accounts(c), & &1.position) == [10, 20, 30]
    {:ok, accepted} = accept(c, review)
    assert accepted["changed_count"] == 3
    assert length(accepted["event_ids"]) == 3
    assert Enum.map(accounts(c), & &1.id) == ids
    assert Enum.map(accounts(c), & &1.position) == [100, 200, 300]

    fields =
      ~w(id number name kind active retired formula formula_refs reserved_numbers vat_entry_id vat_entry_version vat_code category_entry_id category_entry_version category)a

    for old <- before do
      assert Map.take(Repo.get!(Account, old.id), fields) == Map.take(old, fields)
    end

    assert {:ok, %{"replayed" => true}} = accept(c, review)
    assert {:error, :review_already_accepted} = accept(c, review, "another-key")
    assert {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, served} = Setup.get(c.actor, c.tid, c.bid)
    assert Enum.map(served.accounts, & &1["id"]) == ids
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, rebuilt} = Setup.get(c.actor, c.tid, c.bid)
    assert rebuilt.accounts == served.accounts
  end

  test "rebalance can preserve order and a repeated rebalance produces no account events", c do
    ids = Enum.map(accounts(c), & &1.id)
    r = preview(c, ids)
    assert {:ok, _} = accept(c, r)
    {:ok, _} = SetupProjector.deliver(c.tid)
    r = preview(c, ids)
    assert r.plan["changed_count"] == 0
    count = Repo.aggregate(Ep.Events.Event, :count)
    assert {:ok, %{"event_ids" => [], "changed_count" => 0}} = accept(c, r, "no-op")
    assert Repo.aggregate(Ep.Events.Event, :count) == count
  end

  test "duplicates, missing/foreign IDs and retired rows cannot alter chart membership", c do
    {:ok, data} = ChartOrder.get(c.actor, c.tid, c.bid)
    ids = Enum.map(data.rows, & &1["id"])

    for invalid <- [
          [],
          tl(ids),
          [hd(ids), hd(ids), List.last(ids)],
          [Ecto.UUID.generate() | tl(ids)],
          "bad"
        ] do
      assert {:error, :invalid_order} =
               ChartOrder.preview(c.actor, c.tid, c.bid, %{
                 "expected_version" => data.source_version,
                 "ordered_ids" => invalid
               })
    end

    # Retire two rows via a genuine replacement; they cannot be ordered back in.
    {:ok, u} =
      ChartImports.upload(c.actor, c.tid, c.bid, %{
        "headers" => ~w(type number name position),
        "records" => [["posting", "0010", "Bank", "10"]]
      })

    {:ok, p} = ChartImports.preview(c.actor, c.tid, c.bid, u.import_id, %{"mapping" => u.mapping})

    {:ok, _} =
      ChartImports.accept(
        c.actor,
        c.tid,
        c.bid,
        u.import_id,
        %{"digest" => p.digest, "expected_version" => p.expected_version},
        "replace"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = ChartOrder.get(c.actor, c.tid, c.bid)
    assert length(data.rows) == 1

    assert {:error, :invalid_order} =
             ChartOrder.preview(c.actor, c.tid, c.bid, %{
               "expected_version" => data.source_version,
               "ordered_ids" => [List.last(ids)]
             })
  end

  test "revision and digest fences reject stale order reviews without partial writes", c do
    before = accounts(c)
    ids = Enum.map(before, & &1.id)
    old = preview(c, Enum.reverse(ids))

    assert {:error, :digest_conflict} =
             ChartOrder.accept(
               c.actor,
               c.tid,
               c.bid,
               old.review_id,
               %{"digest" => "tampered", "expected_version" => old.expected_version},
               "tampered"
             )

    newer = preview(c, ids)
    {:ok, _} = accept(c, newer, "newer")
    {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:error, :version_conflict} = accept(c, old, "stale")
    assert Enum.map(accounts(c), & &1.id) == ids

    assert {:error, :version_conflict} =
             ChartOrder.preview(c.actor, c.tid, c.bid, %{
               "expected_version" => old.expected_version,
               "ordered_ids" => ids
             })
  end

  test "private purpose/backend/owner checks and receipt recovery survive review cleanup", c do
    r = preview(c, Enum.map(accounts(c), & &1.id))

    assert {:error, :not_found} =
             ChartOrder.review(c.actor, c.tid, c.bid, r.review_id, "other-backend")

    assert {:error, :not_found} =
             ChartOrder.review(sign_in().principal, c.tid, c.bid, r.review_id)

    assert {:error, :not_found} = ChartImports.get(c.actor, c.tid, c.bid, r.review_id)
    assert {:error, :not_found} = ChartOrder.review(c.actor, c.tid, c.bid, c.csv_review.import_id)
    assert {:ok, _} = accept(c, r)
    Repo.delete!(Repo.get!(ChartImport, r.review_id))
    assert {:ok, %{"replayed" => true}} = accept(c, r)
    {:ok, state} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{
          "identity_id" => c.actor.identity_id,
          "active" => false,
          "expected_version" => state.latest_version
        },
        "revoke"
      )

    assert {:error, :not_found} = accept(c, r)
  end

  test "expired reviews cannot accept but may be purged by the shared review cleanup worker", c do
    r = preview(c, Enum.map(accounts(c), & &1.id))

    Repo.update_all(from(i in ChartImport, where: i.id == ^r.review_id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :review_expired} = accept(c, r)

    assert :ok =
             Ep.Finance.ChartImportCleanupWorker.perform(%Oban.Job{
               args: %{"import_id" => r.review_id, "tenant_id" => c.tid}
             })

    assert Repo.get(ChartImport, r.review_id) == nil
  end

  test "ordering includes rows beyond a normal chart page", c do
    records = for n <- 1..60, do: ["posting", "N#{n}", "Extra #{n}", to_string(n * 1000)]

    {:ok, u} =
      ChartImports.upload(c.actor, c.tid, c.bid, %{
        "headers" => ~w(type number name position),
        "records" => records,
        "mode" => "merge"
      })

    {:ok, p} = ChartImports.preview(c.actor, c.tid, c.bid, u.import_id, %{"mapping" => u.mapping})

    {:ok, _} =
      ChartImports.accept(
        c.actor,
        c.tid,
        c.bid,
        u.import_id,
        %{"digest" => p.digest, "expected_version" => p.expected_version},
        "more"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, page} = Setup.accounts(c.actor, c.tid, c.bid)
    assert length(page.accounts) == 50
    {:ok, data} = ChartOrder.get(c.actor, c.tid, c.bid)
    assert length(data.rows) == 63
    ids = data.rows |> Enum.map(& &1["id"]) |> Enum.reverse()
    r = preview(c, ids)
    assert {:ok, _} = accept(c, r)
    assert Enum.map(accounts(c), & &1.id) == ids
  end

  test "inactive current rows participate without being reactivated", c do
    bank = hd(accounts(c))
    {:ok, data} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "account_revise",
        %{
          "account_id" => bank.id,
          "name" => bank.name,
          "kind" => "posting",
          "number" => bank.number,
          "active" => false,
          "expected_account_version" => bank.version,
          "expected_version" => data.latest_version
        },
        "inactive"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = ChartOrder.get(c.actor, c.tid, c.bid)
    assert Enum.find(data.rows, &(&1["id"] == bank.id))["active"] == false
    r = preview(c, data.rows |> Enum.map(& &1["id"]) |> Enum.reverse())
    assert {:ok, _} = accept(c, r)
    refute Repo.get!(Account, bank.id).active
  end
end
