defmodule Ep.Finance.ChartImportsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Account, Books, ChartImport, ChartImports, Setup, SetupProjector}

  setup do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "CSV"}, "tenant")
    tid = t["tenant_id"]

    {:ok, b} =
      Books.create(
        owner.principal,
        tid,
        %{
          "code" => "CSV",
          "name" => "CSV",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = b["book_id"]

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
        "role"
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
    %{actor: owner.principal, tid: tid, bid: bid}
  end

  defp review(c, headers, records) do
    {:ok, upload} =
      ChartImports.upload(c.actor, c.tid, c.bid, %{"headers" => headers, "records" => records})

    {:ok, preview} =
      ChartImports.preview(c.actor, c.tid, c.bid, upload.import_id, %{"mapping" => upload.mapping})

    preview
  end

  defp accept(c, review, key \\ "accept"),
    do:
      ChartImports.accept(
        c.actor,
        c.tid,
        c.bid,
        review.import_id,
        %{"digest" => review.digest, "expected_version" => review.expected_version},
        key
      )

  test "a reviewed mixed batch is atomic, supports forward formulas and gives created accounts event IDs",
       c do
    preview =
      review(c, ~w(type number name position formula), [
        ["calculation", "", "Total", "200", "[0010] * 2"],
        ["posting", "0010", "Bank", "100", ""]
      ])

    assert preview.plan["valid"]
    assert preview.plan["counts"] == %{"create" => 2}
    assert Repo.aggregate(Account, :count) == 0
    assert {:ok, result} = accept(c, preview)
    assert result["stream_version"] == 4
    assert length(result["event_ids"]) == 2
    for id <- result["event_ids"], do: assert(Repo.get!(Account, id))
    assert {:ok, %{"replayed" => true}} = accept(c, preview)
    assert {:error, :import_already_accepted} = accept(c, preview, "another-key")
    assert Repo.aggregate(Account, :count) == 2
    assert {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:ok, data} = Setup.accounts(c.actor, c.tid, c.bid)
    assert Enum.map(data.accounts, & &1["number"]) == ["0010", nil]
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    assert {:ok, %{accounts: accounts}} = Setup.accounts(c.actor, c.tid, c.bid)
    assert accounts == data.accounts
  end

  test "export/import round trip is unchanged, and missing rows never imply deletion", c do
    preview =
      review(c, ~w(type number name position), [
        ["posting", "0010", "Bank", "100"],
        ["header", "", "Other", "200"]
      ])

    {:ok, _} = accept(c, preview)
    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, exported} = ChartImports.export(c.actor, c.tid, c.bid)
    assert exported.row_count == 2

    assert Enum.at(hd(exported.rows), Enum.find_index(exported.columns, &(&1 == "number"))) ==
             "0010"

    again = review(c, exported.columns, exported.rows)
    assert again.plan["counts"] == %{"unchanged" => 2}
    before = Repo.aggregate(Ep.Events.Event, :count)
    {:ok, result} = accept(c, again, "unchanged")
    assert result["event_ids"] == []
    assert Repo.aggregate(Ep.Events.Event, :count) == before
    subset = review(c, exported.columns, [hd(exported.rows)])
    {:ok, _} = accept(c, subset, "subset")
    assert Repo.aggregate(Account, :count) == 2
    {:ok, filtered} = ChartImports.export(c.actor, c.tid, c.bid, %{"q" => "Bank"})
    assert filtered.scope == "filtered" && filtered.row_count == 1
  end

  test "final-chart position swaps commit together and invalid rows make no partial changes", c do
    first =
      review(c, ~w(type number name position), [
        ["posting", "0010", "One", "100"],
        ["posting", "0020", "Two", "200"]
      ])

    {:ok, _} = accept(c, first)
    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, export} = ChartImports.export(c.actor, c.tid, c.bid)
    pos = Enum.find_index(export.columns, &(&1 == "position"))

    rows = [
      List.replace_at(hd(export.rows), pos, "200"),
      List.replace_at(List.last(export.rows), pos, "100")
    ]

    swap = review(c, export.columns, rows)
    assert swap.plan["valid"]
    assert {:ok, _} = accept(c, swap, "swap")
    assert Repo.get_by!(Account, book_id: c.bid, number: "0010").position == 200
    {:ok, _} = SetupProjector.deliver(c.tid)

    invalid =
      review(c, ~w(type number name position), [
        ["posting", "0030", "Valid", "300"],
        ["posting", "0040", "Invalid", "bad"]
      ])

    refute invalid.plan["valid"]
    assert {:error, :invalid_review} = accept(c, invalid, "invalid")
    assert Repo.aggregate(Account, :count) == 2
  end

  test "stale/digest/expiry/private-owner checks never accept an unreviewed plan", c do
    p = review(c, ~w(type number name position), [["posting", "0010", "Bank", "100"]])

    assert {:error, :digest_conflict} =
             ChartImports.accept(
               c.actor,
               c.tid,
               c.bid,
               p.import_id,
               %{"digest" => "tampered", "expected_version" => p.expected_version},
               "bad"
             )

    stranger = sign_in()
    assert {:error, :not_found} = ChartImports.get(stranger.principal, c.tid, c.bid, p.import_id)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "catalogue_create",
        %{"kind" => "vat", "code" => "NEW", "name" => "New", "expected_version" => 2},
        "new"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:error, :version_conflict} = accept(c, p)
    p = review(c, ~w(type number name position), [["posting", "0010", "Bank", "100"]])

    Repo.update_all(from(r in ChartImport, where: r.id == ^p.import_id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :review_expired} = accept(c, p, "expired")

    assert :ok =
             Ep.Finance.ChartImportCleanupWorker.perform(%Oban.Job{
               args: %{"import_id" => p.import_id, "tenant_id" => c.tid}
             })

    assert Repo.get(ChartImport, p.import_id) == nil
  end

  test "duplicates, foreign identities, retired numbers, formulas and unmapped data are reviewed as errors",
       c do
    for records <- [
          [["posting", "0010", "One", "100", ""], ["posting", "0010", "Two", "200", ""]],
          [["posting", "0010", "One", "100", ""], ["posting", "0020", "Two", "100", ""]],
          [["calculation", "", "Invalid", "100", "[9999]"]]
        ] do
      p = review(c, ~w(type number name position formula), records)
      refute p.plan["valid"]
      assert {:error, :invalid_review} = accept(c, p)
    end

    p =
      review(c, ~w(account_id type number name position), [
        [Ecto.UUID.generate(), "posting", "0010", "Unknown", "100"]
      ])

    assert hd(p.plan["rows"])["errors"] == ["unknown_account"]

    p =
      review(c, ~w(book_id type number name position), [
        [Ecto.UUID.generate(), "posting", "0010", "Foreign", "100"]
      ])

    assert hd(p.plan["rows"])["errors"] == ["scope_or_schema_mismatch"]

    assert {:error, :invalid_upload} =
             ChartImports.upload(c.actor, c.tid, c.bid, %{
               "headers" => ["name", "name"],
               "records" => [["a", "b"]]
             })
  end

  test "formula cycles and catalogue references are checked against the complete proposed chart",
       c do
    headers = review(c, ~w(type name position), [["header", "A", "200"], ["header", "B", "300"]])
    {:ok, _} = accept(c, headers, "headers")
    {:ok, _} = SetupProjector.deliver(c.tid)
    [a, b] = Enum.map(headers.plan["rows"], & &1["account_id"])

    cyclic =
      review(c, ~w(account_id type name position formula), [
        [a, "calculation", "A", "200", "[@#{b}]"],
        [b, "calculation", "B", "300", "[@#{a}]"]
      ])

    refute cyclic.plan["valid"]
    assert cyclic.plan["errors"] == ["invalid_formula_cycle_or_reference"]

    unknown =
      review(c, ~w(type number name position vat_entry_id), [
        ["posting", "0010", "Bank", "100", Ecto.UUID.generate()]
      ])

    assert hd(unknown.plan["rows"])["errors"] == ["invalid_catalogue_reference"]

    {:ok, cat} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "catalogue_create",
        %{"kind" => "vat", "code" => "TEST", "name" => "Test", "expected_version" => 4},
        "vat"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    id = hd(cat["event_ids"])

    mismatch =
      review(c, ~w(type number name position vat_entry_id vat_code), [
        ["posting", "0010", "Bank", "100", id, "OTHER"]
      ])

    assert hd(mismatch.plan["rows"])["errors"] == ["catalogue_mismatch"]

    valid =
      review(c, ~w(type number name position vat_code), [
        ["posting", "0010", "Bank", "100", "TEST"]
      ])

    assert valid.plan["valid"]
    assert {:ok, _} = accept(c, valid)
  end

  test "current authority precedes receipt replay, but cleanup does not erase the receipt", c do
    p = review(c, ~w(type number name position), [["posting", "0010", "Bank", "100"]])
    {:ok, result} = accept(c, p)
    Repo.delete!(Repo.get!(ChartImport, p.import_id))
    assert {:ok, %{"replayed" => true}} = accept(c, p)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{
          "identity_id" => c.actor.identity_id,
          "active" => false,
          "expected_version" => result["stream_version"]
        },
        "revoke"
      )

    assert {:error, :not_found} = accept(c, p)
    assert {:ok, _} = SetupProjector.deliver(c.tid)
    # A tenant administrator can still export, without an implicit steward grant.
    assert {:ok, _} = ChartImports.export(c.actor, c.tid, c.bid)
  end

  test "worker page limits never expose half a CSV command", c do
    for {start, count} <- [{1, 499}, {500, 500}] do
      records =
        for n <- start..(start + count - 1),
            do: ["posting", to_string(n), "Account #{n}", to_string(n * 100)]

      p = review(c, ~w(type number name position), records)
      assert p.plan["valid"]
      assert {:ok, _} = accept(c, p, "batch-#{start}")
      assert {:ok, _} = SetupProjector.deliver(c.tid)
    end

    Repo.delete_all(from v in Ep.Finance.SetupView, where: v.tenant_id == ^c.tid)

    Repo.delete_all(
      from i in Ep.Projections.Inbox,
        where: i.tenant_id == ^c.tid and i.consumer == "finance_setup:v1"
    )

    Repo.update_all(from(o in Ep.Events.Outbox, where: o.tenant_id == ^c.tid),
      set: [delivered_at: nil]
    )

    assert {:ok, 1001} = SetupProjector.deliver(c.tid)
    assert {:ok, exported} = ChartImports.export(c.actor, c.tid, c.bid)
    assert exported.row_count == 999
  end
end
