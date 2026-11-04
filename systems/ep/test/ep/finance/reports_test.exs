defmodule Ep.Finance.ReportsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Account,
    Books,
    ChartImports,
    Reports,
    ReportDefinition,
    Setup,
    SetupProjector
  }

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
          ["posting", "0020", "Costs", "20", ""],
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

  defp line(code, kind, ids \\ [], formula \\ "", position \\ 100),
    do: %{
      "id" => nil,
      "code" => code,
      "name" => code,
      "kind" => kind,
      "position" => position,
      "account_ids" => ids,
      "formula" => formula,
      "sign" => 1
    }

  defp draft(c) do
    {:ok, data} = Reports.get(c.actor, c.tid, c.bid)
    p = Enum.find(data.accounts, &(&1["number"] == "0010"))

    %{
      "report_id" => nil,
      "expected_report_version" => nil,
      "expected_version" => data.latest_version,
      "name" => "Profit and loss",
      "active" => true,
      "lines" => [
        line("SALES", "mapping", [p["id"]]),
        line("NET", "total", [], "[SALES] / 3", 200)
      ]
    }
  end

  defp accept(c, review, key \\ "accept") do
    Setup.command(
      c.actor,
      c.tid,
      c.bid,
      "report_save",
      %{
        "review_id" => review.review_id,
        "expected_version" => review.expected_version,
        "digest" => review.digest
      },
      key
    )
  end

  test "private review is not acceptance; accepted reports preserve exact mappings and actor history",
       c do
    before = Repo.aggregate(ReportDefinition, :count)
    {:ok, review} = Reports.review(c.actor, c.tid, c.bid, draft(c))
    assert Repo.aggregate(ReportDefinition, :count) == before
    assert length(review.plan["coverage"]["unmapped"]) == 1

    assert {:error, :not_found} =
             Reports.get_review(sign_in().principal, c.tid, c.bid, review.review_id)

    {:ok, result} = accept(c, review)
    id = hd(result["event_ids"])

    assert Repo.get!(Ep.Finance.ChartImport, review.review_id).accepted_command_id ==
             result["command_id"]

    assert {:ok, %{"replayed" => true}} = accept(c, review)
    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    assert length(data.selected["history"]) == 1
    assert hd(data.selected["history"])["actor_identity_id"] == c.actor.identity_id
    [account] = hd(data.selected["definition"]["lines"])["account_ids"]

    {:ok, preview} =
      Reports.preview(c.actor, c.tid, c.bid, id, %{
        "report_version" => data.selected["version"],
        "balances" => %{account => -1}
      })

    assert hd(preview.results)["amount_minor"] == -1
    assert List.last(preview.results)["exact"] == %{"numerator" => "-1", "denominator" => "3"}
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, rebuilt} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    assert rebuilt.selected == data.selected
  end

  test "coverage flags duplicate mappings and missing inputs propagate without invented zeros",
       c do
    d = draft(c)
    first = hd(d["lines"])

    d = %{
      d
      | "lines" => [first, %{first | "code" => "DUP", "position" => 150}, List.last(d["lines"])]
    }

    {:ok, r} = Reports.review(c.actor, c.tid, c.bid, d)
    assert length(r.plan["coverage"]["multiple"]) == 1
    results = Reports.evaluate(r.plan["definition"], %{})
    assert Enum.all?(results, &(&1["error"] == "missing_balance"))
    id = hd(first["account_ids"])
    results = Reports.evaluate(r.plan["definition"], %{id => 0})
    assert Enum.all?(results, &(&1["amount_minor"] == 0))
  end

  test "revision preserves old labels, line IDs and formula bindings after account changes", c do
    {:ok, r} = Reports.review(c.actor, c.tid, c.bid, draft(c))
    {:ok, accepted} = accept(c, r)
    id = hd(accepted["event_ids"])
    {:ok, _} = SetupProjector.deliver(c.tid)
    old = Repo.get!(ReportDefinition, id)
    posting_id = hd(hd(old.definition["lines"])["account_ids"])
    account = Repo.get!(Account, posting_id)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "account_revise",
        %{
          "account_id" => posting_id,
          "expected_account_version" => account.version,
          "expected_version" => old.version,
          "number" => "0099",
          "name" => "Renamed",
          "kind" => "posting",
          "position" => account.position,
          "active" => true
        },
        "rename"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    lines = old.definition["lines"] |> Enum.map(&Map.drop(&1, ["formula_refs"]))
    [first, total] = lines

    d = %{
      "report_id" => id,
      "expected_report_version" => old.version,
      "expected_version" => data.latest_version,
      "name" => "Revised",
      "active" => false,
      "lines" => [%{first | "code" => "INCOME", "name" => "Income"}, total]
    }

    {:ok, revision} = Reports.review(c.actor, c.tid, c.bid, d)
    assert List.last(revision.plan["definition"]["lines"])["formula_refs"]["SALES"] == first["id"]
    {:ok, _} = accept(c, revision, "revision")
    {:ok, _} = SetupProjector.deliver(c.tid)

    {:ok, historic} =
      Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id, "version" => old.version})

    assert Enum.find(historic.selected["definition"]["accounts"], &(&1["id"] == posting_id))[
             "number"
           ] == "0010"

    {:ok, current} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    assert length(current.selected["history"]) == 2
    assert current.selected["name"] == "Revised"

    {:ok, preview} =
      Reports.preview(c.actor, c.tid, c.bid, id, %{
        "report_version" => old.version,
        "balances" => %{posting_id => 3}
      })

    assert List.last(preview.results)["amount_minor"] == 1

    bad = %{
      d
      | "expected_version" => current.latest_version,
        "expected_report_version" => current.selected["version"],
        "lines" => [line("SALES", "mapping", [], "", 300)]
    }

    assert {:error, :report_code_reserved} = Reports.review(c.actor, c.tid, c.bid, bad)
  end

  test "scope, kind, graph, revision, digest and lifecycle fences reject unsafe changes", c do
    d = draft(c)

    for lines <- [
          [line("A", "total", [], "[B]"), line("B", "total", [], "[A]", 200)],
          [line("A", "total", [], "[MISSING]")],
          [line("A", "mapping", [Ecto.UUID.generate()])],
          [line("A", "header"), line("B", "total", [], "[A]", 200)]
        ] do
      assert {:error, _} = Reports.review(c.actor, c.tid, c.bid, %{d | "lines" => lines})
    end

    assert {:error, :version_conflict} =
             Reports.review(c.actor, c.tid, c.bid, %{d | "expected_version" => 0})

    {:ok, r} = Reports.review(c.actor, c.tid, c.bid, d)

    assert {:error, :digest_conflict} =
             Setup.command(
               c.actor,
               c.tid,
               c.bid,
               "report_save",
               %{
                 "review_id" => r.review_id,
                 "expected_version" => r.expected_version,
                 "digest" => "bad"
               },
               "bad"
             )

    {:ok, result} = accept(c, r)

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

    assert {:error, :not_found} = accept(c, r)
  end

  test "chart replacement preserves historic report meanings and exposes changed coverage", c do
    {:ok, review} = Reports.review(c.actor, c.tid, c.bid, draft(c))
    {:ok, result} = accept(c, review)
    id = hd(result["event_ids"])
    {:ok, _} = SetupProjector.deliver(c.tid)
    report = Repo.get!(ReportDefinition, id)
    old_id = hd(hd(report.definition["lines"])["account_ids"])

    {:ok, upload} =
      ChartImports.upload(c.actor, c.tid, c.bid, %{
        "headers" => ~w(type number name position),
        "records" => [["posting", "0030", "Replacement", "100"]]
      })

    {:ok, replacement} =
      ChartImports.preview(c.actor, c.tid, c.bid, upload.import_id, %{
        "mapping" => upload.mapping,
        "mode" => "replace"
      })

    {:ok, _} =
      ChartImports.accept(
        c.actor,
        c.tid,
        c.bid,
        upload.import_id,
        %{"digest" => replacement.digest, "expected_version" => replacement.expected_version},
        "replace"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    assert data.selected["definition"] == report.definition
    assert old_id in data.current_coverage["unavailable"]
    assert hd(data.current_coverage["unmapped"])["number"] == "0030"

    {:ok, historic} =
      Reports.preview(c.actor, c.tid, c.bid, id, %{
        "report_version" => report.version,
        "balances" => %{old_id => 3}
      })

    assert List.last(historic.results)["amount_minor"] == 1
    {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, rebuilt} = Reports.get(c.actor, c.tid, c.bid, %{"report_id" => id})
    assert rebuilt.selected == data.selected
  end

  test "reviews expire privately while replay still resolves the original accepted receipt", c do
    {:ok, review} = Reports.review(c.actor, c.tid, c.bid, draft(c))
    row = Repo.get!(Ep.Finance.ChartImport, review.review_id)
    Repo.update!(Ecto.Changeset.change(row, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert {:error, :review_expired} = accept(c, review)
    {:ok, fresh} = Reports.review(c.actor, c.tid, c.bid, draft(c))
    {:ok, _} = accept(c, fresh)
    row = Repo.get!(Ep.Finance.ChartImport, fresh.review_id)
    Repo.update!(Ecto.Changeset.change(row, expires_at: DateTime.add(DateTime.utc_now(), -1)))
    assert {:ok, %{"replayed" => true}} = accept(c, fresh)
  end
end
