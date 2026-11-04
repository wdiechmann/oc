defmodule Ep.Finance.JournalsTest do
  use Ep.DataCase, async: true
  import Ecto.Query
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Books,
    ChartImports,
    Journals,
    JournalDraft,
    JournalProjector,
    Periods,
    PeriodProjector,
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

    {:ok, p} =
      Periods.command(
        owner.principal,
        tid,
        bid,
        "create",
        %{
          "name" => "2026",
          "start_date" => "2026-01-01",
          "end_date" => "2026-12-31",
          "expected_version" => 0
        },
        "period"
      )

    {:ok, _} =
      Periods.command(
        owner.principal,
        tid,
        bid,
        "open",
        %{"period_id" => p["period_id"], "expected_version" => 1, "expected_period_version" => 1},
        "open"
      )

    {:ok, _} = PeriodProjector.deliver(tid)

    %{
      actor: owner.principal,
      token: owner.token,
      tid: tid,
      bid: bid,
      csv_review: preview,
      period_id: p["period_id"]
    }
  end

  defp line(id, debit, credit),
    do: %{
      "id" => nil,
      "account_id" => id,
      "debit_minor" => debit,
      "credit_minor" => credit,
      "reference" => "",
      "vat_entry_id" => nil,
      "net_minor" => nil,
      "assessed_vat_minor" => nil
    }

  defp draft(c) do
    {:ok, data} = Journals.get(c.actor, c.tid, c.bid)
    [a, b] = data.accounts

    %{
      "draft_id" => nil,
      "expected_draft_version" => nil,
      "expected_version" => data.latest_version,
      "contexts" => data.contexts,
      "data" => %{
        "name" => "Purchase",
        "posting_date" => "2026-06-01",
        "reference" => "INV-1",
        "lines" => [line(a["id"], 10000, 0), line(b["id"], 0, 10000)]
      }
    }
  end

  defp accept(c, r, key \\ "save"),
    do:
      Journals.accept(
        c.actor,
        c.tid,
        c.bid,
        %{
          "review_id" => r.review_id,
          "digest" => r.digest,
          "expected_version" => r.expected_version
        },
        key
      )

  test "review is private; draft acceptance is atomic, unposted, idempotent and rebuildable", c do
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, draft(c))
    assert Repo.aggregate(JournalDraft, :count) == 0
    assert r.plan["validation"]["status"] == "prepared"
    assert r.plan["validation"]["debit_minor"] == 10000

    assert {:error, :not_found} =
             Journals.get_review(c.actor, c.tid, c.bid, r.review_id, "another-backend")

    {:ok, saved} = accept(c, r)
    assert {:ok, %{"replayed" => true}} = accept(c, r)

    assert Repo.get!(Ep.Finance.ChartImport, r.review_id).accepted_command_id ==
             saved["command_id"]

    {:ok, pending} = Journals.get(c.actor, c.tid, c.bid)
    assert pending.status == "pending"

    assert {:ok, %{status: "pending", requested_draft_pending: true, selected: nil}} =
             Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})

    {:ok, _} = JournalProjector.deliver(c.tid)
    {:ok, data} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})
    assert data.status == "ready"
    assert data.selected["data"]["reference"] == "INV-1"
    assert length(data.selected["history"]) == 1
    assert hd(data.selected["history"])["actor_identity_id"] == c.actor.identity_id

    assert Repo.aggregate(
             from(e in Ep.Events.Event, where: e.event_type == "JournalPosted"),
             :count
           ) == 0

    {:ok, :ok} = JournalProjector.rebuild(c.tid)
    {:ok, rebuilt} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})
    assert rebuilt.selected == data.selected
  end

  test "unfinished journals retain explicit errors instead of silently balancing or posting", c do
    p = draft(c)
    [a, b] = p["data"]["lines"]
    p = put_in(p, ["data", "lines"], [%{a | "debit_minor" => 9000}, %{b | "account_id" => nil}])
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, p)
    assert r.plan["validation"]["status"] == "needs_attention"
    assert r.plan["validation"]["difference_minor"] == -1000
    assert "journal_unbalanced" in r.plan["validation"]["errors"]
    assert "account_required" in List.last(r.plan["validation"]["lines"])["errors"]
    assert {:ok, _} = accept(c, r)
  end

  test "effective VAT is pinned separately from entered amounts; VAT errors remain draft evidence",
       c do
    alias Ep.Finance.{CatalogueEntry, SetupState}
    entry = Repo.get_by!(CatalogueEntry, book_id: c.bid, kind: "vat", code: "input")

    attrs = %{
      "expected_version" => Repo.get!(SetupState, c.bid).version,
      "vat_entry_id" => entry.id,
      "valid_from" => "2026-01-01",
      "valid_until" => nil,
      "direction" => "input",
      "rate_bps" => 2500,
      "deductible_bps" => 5000,
      "mappings" => [%{"box" => "Input VAT", "component" => "deductible_vat", "sign" => 1}]
    }

    {:ok, rule} = Setup.command(c.actor, c.tid, c.bid, "vat_rule_create", attrs, "vat")
    {:ok, _} = SetupProjector.deliver(c.tid)
    p = draft(c)
    [a, b] = p["data"]["lines"]
    p = put_in(p, ["data", "lines"], [%{a | "vat_entry_id" => entry.id, "net_minor" => 10000}, b])
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, p)
    q = hd(r.plan["validation"]["lines"])["vat"]
    assert q["amounts"]["vat"] == 2500
    assert q["amounts"]["deductible_vat"] == 1250
    assert r.plan["validation"]["reporting"] == %{"Input VAT" => 1250}
    assert length(r.plan["data"]["lines"]) == 2
    assert r.plan["validation"]["debit_minor"] == 10000
    {:ok, saved} = accept(c, r)
    {:ok, _} = JournalProjector.deliver(c.tid)
    rule_id = hd(rule["event_ids"])

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "vat_rule_revise",
        Map.merge(attrs, %{
          "rule_id" => rule_id,
          "expected_version" => rule["stream_version"],
          "expected_rule_version" => rule["stream_version"],
          "active" => true,
          "rate_bps" => 2000
        }),
        "vat-revise"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, current} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})
    assert current.validation_stale
    assert hd(current.selected["validation"]["lines"])["vat"]["amounts"]["vat"] == 2500
    p = %{p | "expected_version" => current.latest_version, "contexts" => current.contexts}
    p = put_in(p, ["data", "lines"], [%{a | "vat_entry_id" => entry.id, "net_minor" => nil}, b])
    {:ok, incomplete} = Journals.review(c.actor, c.tid, c.bid, p)
    assert "invalid_amount" in hd(incomplete.plan["validation"]["lines"])["errors"]
    assert incomplete.plan["validation"]["vat_complete"] == false
    assert {:ok, _} = accept(c, incomplete, "incomplete")
  end

  test "period closure invalidates a review and saving a closed-period draft records the issue",
       c do
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, draft(c))

    {:ok, _} =
      Periods.command(
        c.actor,
        c.tid,
        c.bid,
        "close",
        %{"period_id" => c.period_id, "expected_version" => 2, "expected_period_version" => 2},
        "close"
      )

    assert {:error, :view_pending} = accept(c, r)
    {:ok, _} = PeriodProjector.deliver(c.tid)
    assert {:error, :version_conflict} = accept(c, r)
    assert Repo.aggregate(JournalDraft, :count) == 0
    {:ok, closed} = Journals.review(c.actor, c.tid, c.bid, draft(c))
    assert "period_not_open" in closed.plan["validation"]["errors"]
    assert {:ok, _} = accept(c, closed)
  end

  test "scope, amount, version, digest and current authority fences hold before replay", c do
    p = draft(c)
    [a, b] = p["data"]["lines"]

    for value <- [-1, 1.5, "1", 9_000_000_000_001] do
      assert {:error, :invalid_amount} =
               Journals.review(
                 c.actor,
                 c.tid,
                 c.bid,
                 put_in(p, ["data", "lines"], [%{a | "debit_minor" => value}, b])
               )
    end

    assert {:error, :invalid_account_reference} =
             Journals.review(
               c.actor,
               c.tid,
               c.bid,
               put_in(p, ["data", "lines"], [%{a | "account_id" => Ecto.UUID.generate()}, b])
             )

    assert {:error, :version_conflict} =
             Journals.review(c.actor, c.tid, c.bid, %{p | "expected_version" => 99})

    assert {:error, :not_found} = Journals.get(sign_in().principal, c.tid, c.bid)
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, p)

    assert {:error, :digest_conflict} =
             Journals.accept(
               c.actor,
               c.tid,
               c.bid,
               %{
                 "review_id" => r.review_id,
                 "digest" => "bad",
                 "expected_version" => r.expected_version
               },
               "bad"
             )

    {:ok, _} = accept(c, r)
    {:ok, setup} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{
          "identity_id" => c.actor.identity_id,
          "active" => false,
          "expected_version" => setup.latest_version
        },
        "revoke"
      )

    assert {:error, :not_found} = accept(c, r)
  end

  test "draft revisions retain prior account labels, amounts and validation through rebuild", c do
    p = draft(c)
    {:ok, r} = Journals.review(c.actor, c.tid, c.bid, p)
    {:ok, saved} = accept(c, r)
    {:ok, _} = JournalProjector.deliver(c.tid)
    {:ok, data} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})

    revised = %{
      p
      | "draft_id" => saved["draft_id"],
        "expected_draft_version" => saved["stream_version"],
        "expected_version" => data.latest_version,
        "contexts" => data.contexts,
        "data" => %{data.selected["data"] | "name" => "Corrected draft"}
    }

    {:ok, r2} = Journals.review(c.actor, c.tid, c.bid, revised)
    {:ok, _} = accept(c, r2, "revise")
    {:ok, _} = JournalProjector.deliver(c.tid)

    {:ok, historic} =
      Journals.get(c.actor, c.tid, c.bid, %{
        "draft_id" => saved["draft_id"],
        "version" => saved["stream_version"]
      })

    assert historic.selected["data"]["name"] == "Purchase"
    {:ok, before} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})
    assert length(before.selected["history"]) == 2
    {:ok, :ok} = JournalProjector.rebuild(c.tid)
    {:ok, after_rebuild} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => saved["draft_id"]})
    assert before.selected == after_rebuild.selected
  end

  test "import VAT requires a statement assessment and stopped views fail closed", c do
    entry = Repo.get_by!(Ep.Finance.CatalogueEntry, book_id: c.bid, kind: "vat", code: "input")
    {:ok, setup} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "vat_rule_create",
        %{
          "expected_version" => setup.latest_version,
          "vat_entry_id" => entry.id,
          "valid_from" => "2026-01-01",
          "valid_until" => nil,
          "direction" => "reverse_charge",
          "assessment_basis" => "import_statement",
          "rate_bps" => 2500,
          "deductible_bps" => 10000,
          "mappings" => [%{"box" => "Import VAT", "component" => "vat", "sign" => 1}]
        },
        "import-vat"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    p = draft(c)
    [a, b] = p["data"]["lines"]
    p = put_in(p, ["data", "lines"], [%{a | "vat_entry_id" => entry.id, "net_minor" => 10000}, b])
    {:ok, missing} = Journals.review(c.actor, c.tid, c.bid, p)
    assert "assessment_required" in hd(missing.plan["validation"]["lines"])["errors"]

    p =
      put_in(p, ["data", "lines"], [
        %{a | "vat_entry_id" => entry.id, "net_minor" => 10000, "assessed_vat_minor" => 3275},
        b
      ])

    {:ok, assessed} = Journals.review(c.actor, c.tid, c.bid, p)
    assert hd(assessed.plan["validation"]["lines"])["vat"]["amounts"]["vat"] == 3275
    {:ok, _} = accept(c, assessed)
    control = Repo.get_by!(Ep.Projections.Control, tenant_id: c.tid, name: "finance_journals")
    Repo.update!(Ecto.Changeset.change(control, state: "stopped"))
    assert {:error, :view_stopped} = Journals.get(c.actor, c.tid, c.bid)
    assert {:error, :view_stopped} = JournalProjector.deliver(c.tid)
    # A private receipt can still confirm a saved unposted draft while its view is stopped.
    assert {:ok, %{"replayed" => true}} = accept(c, assessed)
  end
end
