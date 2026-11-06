defmodule Ep.Finance.JournalWorkTest do
  use Ep.DataCase, async: true
  import Ecto.Query
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Books,
    ChartImports,
    Journals,
    JournalWork,
    JournalRow,
    JournalCounter,
    JournalRows,
    JournalAttachment,
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

  defp create(c, key \\ "create") do
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid)

    {:ok, r} =
      JournalWork.save(
        c.actor,
        c.tid,
        c.bid,
        "create",
        %{
          "expected_version" => d.latest_version,
          "contexts" => d.contexts,
          "data" => %{"name" => key, "posting_date" => "2026-06-01", "reference" => ""}
        },
        key
      )

    {:ok, _} = JournalProjector.deliver(c.tid)
    r["draft_id"]
  end

  defp row(c, id \\ nil) do
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid)
    [a, b] = d.accounts

    %{
      "id" => id,
      "reference" => "Enclosure",
      "debit_account_id" => a["id"],
      "credit_account_id" => b["id"],
      "amount_minor" => 12500,
      "amount_basis" => "gross",
      "void" => false
    }
  end

  defp body(c, did, row) do
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})

    %{
      "draft_id" => did,
      "expected_version" => d.latest_version,
      "expected_draft_version" => d.selected["version"],
      "contexts" => d.contexts,
      "row" => row
    }
  end

  defp save(c, did, row, key) do
    {:ok, r} = JournalWork.save(c.actor, c.tid, c.bid, "row", body(c, did, row), key)
    {:ok, _} = JournalProjector.deliver(c.tid)
    r
  end

  test "confirmed posting rolls up accounts, preserves IDs and is immutable and idempotent", c do
    did = create(c)
    save(c, did, row(c), "post-row-one")
    # Enter saves the completed row and prepends an untouched numbered row.
    payload = body(c, did, row(c)) |> Map.put("append_row", true)
    assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "row", payload, "post-row-two")
    {:ok, _} = JournalProjector.deliver(c.tid)
    alias Ep.Finance.JournalPosting
    {:ok, plan} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    assert plan["errors"] == []
    assert plan["row_errors"] == []
    assert length(Repo.get!(JournalDraft, did).data["rows"]) == 3
    assert length(plan["accounts"]) == 2
    assert Enum.sort(Enum.map(plan["accounts"], & &1["post_minor"])) == [-25000, 25000]

    assert Enum.all?(
             plan["accounts"],
             &(&1["prepost_minor"] == 0 && &1["postpost_minor"] == &1["post_minor"])
           )

    attrs = Map.take(plan, ~w(contexts digest draft_id expected_draft_version expected_version))
    numbers = Repo.all(from r in JournalRow, select: r.posting_id, order_by: r.posting_id)

    assert {:error, :forced_post_rollback} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        JournalWork.save(c.actor, c.tid, c.bid, "post", attrs, "rolled-back-post")

               Repo.rollback(:forced_post_rollback)
             end)

    refute Repo.get!(JournalDraft, did).data["posted"]
    assert {:ok, result} = JournalWork.save(c.actor, c.tid, c.bid, "post", attrs, "post-confirm")
    assert result["posted"]
    assert {:ok, replay} = JournalWork.save(c.actor, c.tid, c.bid, "post", attrs, "post-confirm")
    assert replay["replayed"]
    assert replay["event_ids"] == result["event_ids"]
    assert Repo.all(from r in JournalRow, select: r.posting_id, order_by: r.posting_id) == numbers
    {:ok, _} = JournalProjector.deliver(c.tid)

    assert {:error, :journal_already_posted} =
             JournalWork.save(c.actor, c.tid, c.bid, "post", attrs, "post-again")

    assert {:error, :journal_already_posted} =
             JournalWork.save(c.actor, c.tid, c.bid, "row", body(c, did, row(c)), "edit-posted")

    {:ok, data} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})
    assert data.selected["data"]["posted"]
    assert data.selected["data"]["authorized_by"] == c.actor.identity_id
    assert data.selected["data"]["verified_by"] == c.actor.identity_id
    assert {:ok, :ok} = JournalProjector.rebuild(c.tid)
    second = create(c, "second-journal")
    save(c, second, row(c), "second-line")
    {:ok, next} = JournalPosting.impact(c.actor, c.tid, c.bid, second)
    assert Enum.sort(Enum.map(next["accounts"], & &1["prepost_minor"])) == [-25000, 25000]
    assert Enum.sort(Enum.map(next["accounts"], & &1["postpost_minor"])) == [-37500, 37500]
  end

  test "posting refuses incomplete or changed journals without ledger effects", c do
    alias Ep.Finance.JournalPosting
    did = create(c)
    {:ok, incomplete} = JournalPosting.impact(c.actor, c.tid, c.bid, did)

    attrs =
      Map.take(incomplete, ~w(contexts digest draft_id expected_draft_version expected_version))

    assert {:error, :journal_not_postable} =
             JournalPosting.post(c.actor, c.tid, c.bid, attrs, "incomplete")

    save(c, did, row(c), "valid-row")
    {:ok, plan} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    attrs = Map.take(plan, ~w(contexts digest draft_id expected_draft_version expected_version))
    save(c, did, row(c), "changed-after-preview")

    assert {:error, :version_conflict} =
             JournalPosting.post(c.actor, c.tid, c.bid, attrs, "stale-post")

    refute Repo.get!(JournalDraft, did).data["posted"]

    assert Repo.aggregate(
             from(e in Ep.Events.Event,
               where: e.tenant_id == ^c.tid and e.event_type == "JournalPosted"
             ),
             :count
           ) == 0
  end

  test "posting labels incomplete numbered rows instead of ignoring entered work", c do
    alias Ep.Finance.JournalPosting
    did = create(c)
    save(c, did, row(c), "complete-row")

    partial = %{
      row(c)
      | "reference" => "Unfinished receipt",
        "debit_account_id" => nil,
        "credit_account_id" => nil,
        "amount_minor" => 0
    }

    result = save(c, did, partial, "unfinished-row")
    {:ok, impact} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    assert [issue] = impact["row_errors"]
    assert issue["posting_id"] == result["posting_id"]
    assert issue["row_id"] == result["row_id"]
    assert "account_required" in issue["errors"]
    assert "choose_one_nonzero_side" in issue["errors"]
    attrs = Map.take(impact, ~w(contexts digest draft_id expected_draft_version expected_version))

    assert {:error, :journal_not_postable} =
             JournalPosting.post(c.actor, c.tid, c.bid, attrs, "unfinished-post")
  end

  test "posting checks current authority and protects against period closure", c do
    alias Ep.Finance.JournalPosting
    did = create(c)
    save(c, did, row(c), "before-close")
    {:ok, plan} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    attrs = Map.take(plan, ~w(contexts digest draft_id expected_draft_version expected_version))
    stranger = sign_in()
    assert {:error, :not_found} = JournalPosting.impact(stranger.principal, c.tid, c.bid, did)

    assert {:error, :not_found} =
             JournalPosting.post(stranger.principal, c.tid, c.bid, attrs, "unauthorized")

    assert {:ok, _} =
             Periods.command(
               c.actor,
               c.tid,
               c.bid,
               "close",
               %{
                 "period_id" => c.period_id,
                 "expected_version" => 2,
                 "expected_period_version" => 2
               },
               "close-before-post"
             )

    assert {:error, :view_pending} =
             JournalPosting.post(c.actor, c.tid, c.bid, attrs, "closed-pending")

    {:ok, _} = PeriodProjector.deliver(c.tid)

    assert {:error, :version_conflict} =
             JournalPosting.post(c.actor, c.tid, c.bid, attrs, "closed-stale")

    {:ok, closed} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    assert "period_not_open" in closed["errors"]

    assert {:error, :journal_not_postable} =
             JournalPosting.post(
               c.actor,
               c.tid,
               c.bid,
               Map.take(closed, Map.keys(attrs)),
               "closed-post"
             )

    refute Repo.get!(JournalDraft, did).data["posted"]
  end

  test "save and next allocates exactly one new line atomically and replays both IDs", c do
    did = create(c)
    save(c, did, row(c), "first")
    old = Repo.one!(JournalRow)

    payload =
      body(c, did, Map.put(row(c, old.id), "reference", "Completed"))
      |> Map.put("append_row", true)

    assert {:error, :forced} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        JournalWork.save(c.actor, c.tid, c.bid, "row", payload, "rollback-next")

               Repo.rollback(:forced)
             end)

    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    assert {:ok, result} = JournalWork.save(c.actor, c.tid, c.bid, "row", payload, "next")
    assert result["row_id"] == old.id
    assert result["posting_id"] == 1
    assert result["next_posting_id"] == 2

    assert {:ok, %{"replayed" => true, "next_row_id" => next_id}} =
             JournalWork.save(c.actor, c.tid, c.bid, "row", payload, "next")

    assert next_id == result["next_row_id"]
    assert Repo.get!(JournalCounter, c.bid).last_number == 2
    [next, edited] = Repo.get!(JournalDraft, did).data["rows"]
    assert next["id"] == next_id
    assert next["amount_minor"] == 0
    assert edited["reference"] == "Completed"
  end

  test "initial empty line has an immutable posting ID and accepts attachments immediately", c do
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid)

    request = %{
      "initial_row" => true,
      "expected_version" => d.latest_version,
      "contexts" => d.contexts,
      "data" => %{
        "name" => "Ready for enclosures",
        "posting_date" => "2026-06-01",
        "reference" => ""
      }
    }

    assert {:ok, result} = JournalWork.save(c.actor, c.tid, c.bid, "create", request, "initial")
    assert result["posting_id"] == 1

    assert {:ok, %{"replayed" => true, "row_id" => row_id}} =
             JournalWork.save(c.actor, c.tid, c.bid, "create", request, "initial")

    assert row_id == result["row_id"]
    did = result["draft_id"]
    [initial] = Repo.get!(JournalDraft, did).data["rows"]
    assert initial["id"] == row_id
    assert initial["amount_minor"] == 0
    assert is_nil(initial["debit_account_id"])

    assert {:ok, upload} =
             JournalWork.stage(c.actor, c.tid, c.bid, row_id, %{
               "filename" => "first.pdf",
               "content_type" => "application/pdf",
               "content" => Base.encode64("%PDF-1.4\nEnclosure before entry")
             })

    {:ok, _} = JournalProjector.deliver(c.tid)
    payload = body(c, did, row(c)) |> Map.delete("row") |> Map.put("upload_id", upload.upload_id)
    assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "attachment", payload, "first-file")
    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    assert Repo.one!(JournalAttachment).row_id == row_id
    assert hd(Repo.get!(JournalDraft, did).data["rows"])["posting_id"] == 1
  end

  test "metadata creates an empty work journal and saved rows share one unbroken book sequence",
       c do
    did = create(c)
    assert Repo.get!(JournalDraft, did).data["rows"] == []
    assert Repo.get!(JournalCounter, c.bid).last_number == 0
    save(c, did, row(c), "row1")
    first = Repo.one!(from r in JournalRow, where: r.draft_id == ^did)
    assert first.posting_id == 1
    b = body(c, did, row(c))

    assert {:error, :invalid_journal} =
             JournalWork.save(
               c.actor,
               c.tid,
               c.bid,
               "row",
               put_in(b, ["row", "amount_minor"], -9_000_000_000_001),
               "invalid"
             )

    assert {:error, :forced} =
             Repo.transaction(fn ->
               assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "row", b, "rollback")
               assert Repo.get!(JournalCounter, c.bid).last_number == 2
               Repo.rollback(:forced)
             end)

    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "row", b, "row2")

    assert {:ok, %{"replayed" => true}} =
             JournalWork.save(c.actor, c.tid, c.bid, "row", b, "row2")

    {:ok, _} = JournalProjector.deliver(c.tid)
    did2 = create(c, "another-journal")
    save(c, did2, row(c), "row3")
    saved = JournalRows.input(first.data) |> Map.put("void", true)
    save(c, did, saved, "void")
    assert Repo.get!(JournalRow, first.id).data["void"]

    assert Repo.all(from r in JournalRow, order_by: r.posting_id, select: r.posting_id) == [
             1,
             2,
             3
           ]

    assert Repo.get!(JournalCounter, c.bid).last_number == 3
    assert {:ok, :ok} = JournalProjector.rebuild(c.tid)
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})
    assert Enum.map(d.selected["data"]["rows"], & &1["posting_id"]) == [2, 1]
    assert List.last(d.selected["data"]["rows"])["void"]
  end

  test "lookup preserves account numbers and read-only previews allocate no numbers", c do
    assert_raise RuntimeError, fn ->
      JournalRows.assign!(c.tid, c.bid, Ecto.UUID.generate(), %{"rows" => []})
    end

    did = create(c)

    assert {:ok, %{results: [%{"number" => "0010"}]}} =
             JournalWork.lookup(c.actor, c.tid, c.bid, "0010")

    assert {:ok, %{results: [%{"number" => "0010"}]}} =
             JournalWork.lookup(c.actor, c.tid, c.bid, "01")

    assert {:ok, %{results: [%{"name" => "Bank"}]}} =
             JournalWork.lookup(c.actor, c.tid, c.bid, "AN")

    assert {:ok, %{results: []}} = JournalWork.lookup(c.actor, c.tid, c.bid, "1")
    assert {:ok, %{results: []}} = JournalWork.lookup(c.actor, c.tid, c.bid, ".*")
    p = body(c, did, row(c)) |> Map.delete("expected_version")
    assert {:ok, %{row: %{"posting_id" => nil}}} = Journals.preview_row(c.actor, c.tid, c.bid, p)
    assert Repo.aggregate(JournalRow, :count) == 0
    assert Repo.get!(JournalCounter, c.bid).last_number == 0
    {:ok, setup} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "account_create",
        %{
          "expected_version" => setup.latest_version,
          "kind" => "posting",
          "number" => "1",
          "name" => "Short account",
          "position" => 40
        },
        "short-account"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)

    assert {:ok, %{results: [%{"number" => "1"}]}} =
             JournalWork.lookup(c.actor, c.tid, c.bid, "1")

    assert {:ok, %{results: []}} = JournalWork.lookup(c.actor, c.tid, c.bid, "0")
  end

  test "account-driven VAT included in amount uses exact gross rounding", c do
    did = create(c)
    account = Repo.get_by!(Ep.Finance.Account, book_id: c.bid, number: "0010")
    vat = Repo.get_by!(Ep.Finance.CatalogueEntry, book_id: c.bid, kind: "vat", code: "input")
    {:ok, s} = Setup.get(c.actor, c.tid, c.bid)

    {:ok, r} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "vat_rule_create",
        %{
          "expected_version" => s.latest_version,
          "vat_entry_id" => vat.id,
          "valid_from" => "2026-01-01",
          "valid_until" => nil,
          "direction" => "input",
          "rate_bps" => 2500,
          "deductible_bps" => 10000,
          "mappings" => [%{"box" => "Input VAT", "component" => "vat", "sign" => 1}]
        },
        "rule"
      )

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "account_revise",
        %{
          "expected_version" => r["stream_version"],
          "expected_account_version" => account.version,
          "account_id" => account.id,
          "kind" => "posting",
          "number" => account.number,
          "name" => account.name,
          "position" => account.position,
          "active" => true,
          "vat_entry_id" => vat.id,
          "vat_basis" => "gross"
        },
        "assign"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)

    assert {:ok, %{results: [%{"number" => "0010"}]}} =
             JournalWork.lookup(c.actor, c.tid, c.bid, "NPUT")

    save(c, did, Map.merge(row(c), %{"amount_basis" => nil, "basis_override" => false}), "gross")
    draft = Repo.get!(JournalDraft, did)
    q = hd(draft.validation["lines"])["vat"]
    assert q["amounts"]["vat"] == 2500
    assert q["amounts"]["net"] == 10000
    [saved] = draft.data["rows"]
    assert saved["credit_total_minor"] == 12500
    assert saved["amount_basis"] == "gross"
    refute saved["basis_override"]

    save(
      c,
      did,
      Map.merge(row(c, saved["id"]), %{"amount_basis" => "net", "basis_override" => true}),
      "override"
    )

    overridden = Repo.get!(JournalDraft, did)
    assert hd(overridden.validation["lines"])["vat"]["amounts"]["vat"] == 3125
    assert hd(overridden.data["rows"])["credit_total_minor"] == 15625
    assert List.last(overridden.data["lines"])["credit_minor"] == 15625

    save(
      c,
      did,
      Map.merge(row(c, saved["id"]), %{
        "amount_basis" => "net",
        "basis_override" => true,
        "credit_amount_minor" => 15000
      }),
      "custom-credit"
    )

    custom = Repo.get!(JournalDraft, did)
    assert hd(custom.data["rows"])["suggested_credit_minor"] == 15625
    assert hd(custom.data["rows"])["credit_total_minor"] == 15000
    assert hd(custom.data["rows"])["posting_id"] == saved["posting_id"]
    assert "posting_preview_unbalanced" in custom.validation["posting_preview"]["errors"]

    for {amount, credit, vat_amount, direction} <- [
          {112_500, 112_500, 22500, "input"},
          {-112_500, 112_500, 22500, "input"}
        ] do
      save(
        c,
        did,
        Map.merge(row(c, saved["id"]), %{
          "amount_minor" => amount,
          "amount_basis" => "gross",
          "basis_override" => true
        }),
        "split-#{amount}"
      )

      split = Repo.get!(JournalDraft, did)
      assert hd(split.data["rows"])["credit_total_minor"] == credit
      quote = hd(split.validation["lines"])["vat"]
      assert quote["amounts"]["vat"] == vat_amount
      assert quote["posting_direction"] == direction
      assert hd(split.data["rows"])["posting_id"] == saved["posting_id"]

      if amount < 0 do
        assert hd(split.data["lines"])["debit_minor"] == 112_500
        assert List.last(split.data["lines"])["credit_minor"] == 112_500
      end
    end

    assert Repo.get!(Ep.Finance.Account, account.id).vat_basis == "gross"
    {:ok, setup} = Setup.get(c.actor, c.tid, c.bid)
    current = Repo.get!(Ep.Finance.Account, account.id)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "account_revise",
        %{
          "expected_version" => setup.latest_version,
          "expected_account_version" => current.version,
          "account_id" => current.id,
          "kind" => "posting",
          "number" => current.number,
          "name" => current.name,
          "position" => current.position,
          "active" => true,
          "vat_basis" => nil,
          "vat_entry_id" => vat.id
        },
        "unspecified"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)

    save(
      c,
      did,
      Map.merge(row(c, saved["id"]), %{"amount_basis" => nil, "basis_override" => false}),
      "unspecified-row"
    )

    unspecified = Repo.get!(JournalDraft, did)
    assert hd(unspecified.validation["lines"])["vat"]["error"] == "vat_basis_required"
    assert hd(unspecified.data["rows"])["posting_id"] == saved["posting_id"]
    assert is_nil(hd(unspecified.data["rows"])["credit_total_minor"])
    rule = Repo.get!(Ep.Finance.VatRule, hd(r["event_ids"]))

    assert {:ok, %{amounts: %{"net" => 2, "vat" => 0}}} =
             Ep.Finance.VatRules.calculate_gross(rule, ~D[2026-06-01], 2)
  end

  test "attachment stages remain private and accepted enclosures retain their posting link", c do
    did = create(c)
    save(c, did, row(c), "row")
    entry = Repo.one!(JournalRow)
    content = "%PDF-1.4\nSynthetic enclosure"

    p = %{
      "filename" => "receipt.pdf",
      "content_type" => "application/pdf",
      "content" => Base.encode64(content)
    }

    {:ok, upload} = JournalWork.stage(c.actor, c.tid, c.bid, entry.id, p)
    assert Repo.aggregate(JournalAttachment, :count) == 0
    b = body(c, did, row(c)) |> Map.delete("row") |> Map.put("upload_id", upload.upload_id)

    assert {:error, :not_found} =
             JournalWork.save(c.actor, c.tid, c.bid, "attachment", b, "wrong", "other-backend")

    assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "attachment", b, "attach")

    assert {:ok, %{"replayed" => true}} =
             JournalWork.save(c.actor, c.tid, c.bid, "attachment", b, "attach")

    assert Repo.aggregate(JournalAttachment, :count) == 1
    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    a = Repo.one!(JournalAttachment)
    assert {:ok, %{content: encoded}} = JournalWork.download(c.actor, c.tid, c.bid, a.id)
    assert Base.decode64!(encoded) == content
    assert {:error, :not_found} = JournalWork.download(sign_in().principal, c.tid, c.bid, a.id)

    assert {:error, :invalid_attachment} =
             JournalWork.stage(c.actor, c.tid, c.bid, entry.id, %{
               p
               | "content" => Base.encode64("<html>")
             })

    assert Repo.get!(JournalDraft, did).data["rows"] |> hd() |> Map.get("attachments") |> length() ==
             1
  end

  test "another book starts its own sequence and numbered rows cannot be removed", c do
    did = create(c)
    save(c, did, row(c), "first")
    {:ok, d} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})

    body = %{
      "draft_id" => did,
      "expected_draft_version" => d.selected["version"],
      "expected_version" => d.latest_version,
      "contexts" => d.contexts,
      "data" =>
        Map.take(d.selected["data"], ~w(name posting_date reference)) |> Map.put("rows", [])
    }

    {:ok, review} = Journals.review(c.actor, c.tid, c.bid, body)

    assert {:error, :numbered_row_cannot_disappear} =
             Journals.accept(
               c.actor,
               c.tid,
               c.bid,
               %{
                 "review_id" => review.review_id,
                 "expected_version" => review.expected_version,
                 "digest" => review.digest
               },
               "remove"
             )

    assert Repo.get!(JournalCounter, c.bid).last_number == 1

    {:ok, book} =
      Books.create(
        c.actor,
        c.tid,
        %{
          "name" => "Other",
          "code" => "OTHER",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "other-book"
      )

    bid = book["book_id"]

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => true, "expected_version" => 0},
        "grant2"
      )

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "init2"
      )

    for i <- 1..2 do
      assert {:ok, _} =
               Setup.command(
                 c.actor,
                 c.tid,
                 bid,
                 "account_create",
                 %{
                   "expected_version" => i + 1,
                   "kind" => "posting",
                   "number" => "00#{i}",
                   "name" => "Account #{i}",
                   "position" => i * 100
                 },
                 "account#{i}"
               )
    end

    {:ok, _} = SetupProjector.deliver(c.tid)
    foreign = Repo.get_by!(Ep.Finance.Account, book_id: bid, number: "001")
    {:ok, state} = Setup.get(c.actor, c.tid, c.bid)
    vat = Repo.get_by!(Ep.Finance.CatalogueEntry, book_id: c.bid, kind: "vat", code: "input")

    assert {:error, :invalid_vat_posting_account} =
             Setup.command(
               c.actor,
               c.tid,
               c.bid,
               "vat_rule_create",
               %{
                 "expected_version" => state.latest_version,
                 "vat_entry_id" => vat.id,
                 "valid_from" => "2026-01-01",
                 "valid_until" => nil,
                 "direction" => "input",
                 "rate_bps" => 2500,
                 "deductible_bps" => 10000,
                 "mappings" => [%{"box" => "VAT", "component" => "vat", "sign" => 1}],
                 "posting_accounts" => %{"input" => foreign.id}
               },
               "foreign-vat-account"
             )

    other = %{c | bid: bid}
    did2 = create(other, "other-create")
    save(other, did2, row(other), "other-row")
    assert Repo.get!(JournalCounter, bid).last_number == 1
    assert Repo.all(from r in JournalRow, where: r.draft_id == ^did2, select: r.posting_id) == [1]
  end

  test "header corrections revalidate without changing posting IDs", c do
    did = create(c)
    save(c, did, row(c), "row")

    p =
      body(c, did, row(c))
      |> Map.delete("row")
      |> Map.put("data", %{
        "name" => "Corrected",
        "posting_date" => "2026-06-02",
        "reference" => "REF"
      })

    assert {:ok, _} = JournalWork.save(c.actor, c.tid, c.bid, "details", p, "details")
    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    draft = Repo.get!(JournalDraft, did)
    assert draft.data["name"] == "Corrected"
    assert hd(draft.data["rows"])["posting_id"] == 1
  end

  defp posting_setup(c, direction \\ "input", deductible \\ 10000) do
    command = fn action, attrs, key ->
      {:ok, state} = Setup.get(c.actor, c.tid, c.bid)

      {:ok, result} =
        Setup.command(
          c.actor,
          c.tid,
          c.bid,
          action,
          Map.put(attrs, "expected_version", state.latest_version),
          key
        )

      result
    end

    accounts =
      Map.new(Enum.with_index(~w(input output non_deductible), 4), fn {role, n} ->
        command.(
          "account_create",
          %{"kind" => "posting", "number" => "T#{n}", "name" => role, "position" => n * 10},
          "account-#{role}"
        )

        {role, Repo.get_by!(Ep.Finance.Account, book_id: c.bid, number: "T#{n}").id}
      end)

    vat = Repo.get_by!(Ep.Finance.CatalogueEntry, book_id: c.bid, kind: "vat", code: "input")

    attrs = %{
      "vat_entry_id" => vat.id,
      "valid_from" => "2026-01-01",
      "valid_until" => nil,
      "direction" => direction,
      "rate_bps" => 2500,
      "deductible_bps" => deductible,
      "mappings" => [%{"box" => "VAT", "component" => "vat", "sign" => 1}],
      "posting_accounts" => accounts
    }

    result = command.("vat_rule_create", attrs, "posting-rule")
    rule = Repo.get!(Ep.Finance.VatRule, hd(result["event_ids"]))
    debit = Repo.get_by!(Ep.Finance.Account, book_id: c.bid, number: "0010")
    credit = Repo.get_by!(Ep.Finance.Account, book_id: c.bid, number: "0020")

    command.(
      "account_revise",
      %{
        "account_id" => debit.id,
        "expected_account_version" => debit.version,
        "active" => true,
        "kind" => "posting",
        "number" => debit.number,
        "name" => debit.name,
        "position" => debit.position,
        "vat_entry_id" => vat.id,
        "vat_basis" => "gross"
      },
      "assign-posting-vat"
    )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {accounts, rule, attrs, debit, credit, command}
  end

  test "complete posting preview balances gross net and signed VAT without posting", c do
    {accounts, rule, _, debit, credit, command} = posting_setup(c)
    did = create(c)

    p = %{
      "id" => nil,
      "reference" => "Preview",
      "debit_account_id" => debit.id,
      "credit_account_id" => credit.id,
      "amount_minor" => 112_500,
      "amount_basis" => "gross",
      "basis_override" => true,
      "credit_amount_minor" => nil,
      "void" => false
    }

    save(c, did, p, "gross-preview")
    [saved] = Repo.get!(JournalDraft, did).data["rows"]

    for {amount, basis, total, net, tax, role} <- [
          {112_500, "gross", 112_500, 90000, 22500, "vat_input"},
          {90000, "net", 112_500, 90000, 22500, "vat_input"},
          {-112_500, "gross", 112_500, 90000, 22500, "vat_input"}
        ] do
      save(
        c,
        did,
        %{p | "id" => saved["id"], "amount_minor" => amount, "amount_basis" => basis},
        "preview-#{amount}-#{basis}"
      )

      preview = Repo.get!(JournalDraft, did).validation["posting_preview"]
      assert preview["status"] == "complete"
      assert preview["balanced"]
      assert preview["debit_minor"] == total
      assert preview["credit_minor"] == total
      [row] = preview["rows"]
      assert row["posting_id"] == saved["posting_id"]
      assert row["vat_rule"]["rule_version"] == rule.version
      [net_leg, _, tax_leg] = row["legs"]
      assert net_leg["debit_minor"] + net_leg["credit_minor"] == net
      assert tax_leg["role"] == role
      assert tax_leg["debit_minor"] + tax_leg["credit_minor"] == tax
      assert tax_leg["account"]["id"] == accounts["input"]
    end

    maximum =
      body(c, did, %{
        p
        | "id" => saved["id"],
          "amount_minor" => 9_000_000_000_000,
          "amount_basis" => "net"
      })
      |> Map.delete("expected_version")

    assert {:error, :invalid_amount} = Journals.preview_row(c.actor, c.tid, c.bid, maximum)
    {:ok, projected} = Ep.Finance.VatRules.get(c.actor, c.tid, c.bid)
    assert hd(projected.vat_rules)["posting_accounts"] == accounts
    assert hd(hd(projected.vat_rules)["history"])["posting_accounts"] == accounts
    mapped = Repo.get!(Ep.Finance.Account, accounts["input"])

    command.(
      "account_revise",
      %{
        "account_id" => mapped.id,
        "expected_account_version" => mapped.version,
        "active" => false,
        "kind" => "posting",
        "number" => mapped.number,
        "name" => mapped.name,
        "position" => mapped.position
      },
      "deactivate-mapped"
    )

    {:ok, _} = SetupProjector.deliver(c.tid)
    request = body(c, did, %{p | "id" => saved["id"]}) |> Map.delete("expected_version")
    assert {:ok, %{validation: validation}} = Journals.preview_row(c.actor, c.tid, c.bid, request)
    assert "posting_account_unavailable:vat_input" in validation["posting_preview"]["errors"]
    assert Repo.get!(JournalCounter, c.bid).last_number == 1
  end

  test "partial deduction reverse charge and missing mappings are explicit in previews", c do
    {accounts, rule, attrs, debit, credit, _} = posting_setup(c, "reverse_charge", 5000)
    did = create(c)

    p = %{
      "id" => nil,
      "reference" => "Reverse",
      "debit_account_id" => debit.id,
      "credit_account_id" => credit.id,
      "amount_minor" => 90000,
      "amount_basis" => "net",
      "basis_override" => true,
      "credit_amount_minor" => nil,
      "void" => false
    }

    save(c, did, p, "reverse-preview")
    draft = Repo.get!(JournalDraft, did)
    assert draft.validation["posting_preview"]["status"] == "complete"
    [row] = draft.validation["posting_preview"]["rows"]

    assert Enum.map(row["legs"], & &1["role"]) ==
             ~w(debit credit vat_output vat_input vat_non_deductible)

    assert Enum.map(Enum.drop(row["legs"], 2), &(&1["debit_minor"] + &1["credit_minor"])) == [
             22500,
             11250,
             11250
           ]

    {:ok, state} = Setup.get(c.actor, c.tid, c.bid)

    revised =
      Map.merge(attrs, %{
        "expected_version" => state.latest_version,
        "rule_id" => rule.id,
        "expected_rule_version" => rule.version,
        "active" => true,
        "posting_accounts" => %{"input" => accounts["input"]}
      })

    assert {:ok, _} =
             Setup.command(c.actor, c.tid, c.bid, "vat_rule_revise", revised, "missing-output")

    {:ok, _} = SetupProjector.deliver(c.tid)

    request =
      body(c, did, %{p | "id" => hd(draft.data["rows"])["id"]}) |> Map.delete("expected_version")

    assert {:ok, %{validation: validation}} = Journals.preview_row(c.actor, c.tid, c.bid, request)
    assert "vat_posting_account_missing:output" in validation["posting_preview"]["errors"]
    assert validation["posting_preview"]["status"] == "needs_attention"
    {:ok, state} = Setup.get(c.actor, c.tid, c.bid)
    current = Repo.get!(Ep.Finance.VatRule, rule.id)

    invalid =
      Map.merge(revised, %{
        "expected_version" => state.latest_version,
        "expected_rule_version" => current.version,
        "posting_accounts" => %{
          "input" => Repo.get_by!(Ep.Finance.Account, book_id: c.bid, kind: "calculation").id
        }
      })

    assert {:error, :invalid_vat_posting_account} =
             Setup.command(c.actor, c.tid, c.bid, "vat_rule_revise", invalid, "not-posting")

    normal =
      Map.merge(revised, %{
        "expected_version" => state.latest_version,
        "expected_rule_version" => current.version,
        "direction" => "input",
        "posting_accounts" => accounts
      })

    assert {:ok, _} =
             Setup.command(c.actor, c.tid, c.bid, "vat_rule_revise", normal, "partial-input")

    {:ok, _} = SetupProjector.deliver(c.tid)

    request =
      body(c, did, %{p | "id" => hd(draft.data["rows"])["id"]}) |> Map.delete("expected_version")

    assert {:ok, %{validation: validation}} = Journals.preview_row(c.actor, c.tid, c.bid, request)
    assert validation["posting_preview"]["status"] == "complete"
    [partial] = validation["posting_preview"]["rows"]

    assert Enum.map(partial["legs"], & &1["role"]) ==
             ~w(debit credit vat_input vat_non_deductible)

    assert partial["debit_minor"] == 112_500
    assert partial["credit_minor"] == 112_500

    for {direction, share, role, amount, leg_count} <- [
          {"input", 5000, "debit", 101_250, 3},
          {"input", 0, "debit", 112_500, 2},
          {"reverse_charge", 5000, "debit", 101_250, 4}
        ] do
      {:ok, state} = Setup.get(c.actor, c.tid, c.bid)
      current = Repo.get!(Ep.Finance.VatRule, rule.id)

      follow =
        Map.merge(normal, %{
          "expected_version" => state.latest_version,
          "expected_rule_version" => current.version,
          "direction" => direction,
          "deductible_bps" => share,
          "posting_accounts" => Map.put(accounts, "non_deductible", nil)
        })

      assert {:ok, _} =
               Setup.command(
                 c.actor,
                 c.tid,
                 c.bid,
                 "vat_rule_revise",
                 follow,
                 "follow-#{direction}-#{share}"
               )

      {:ok, _} = SetupProjector.deliver(c.tid)

      request =
        body(c, did, %{p | "id" => hd(draft.data["rows"])["id"]})
        |> Map.delete("expected_version")

      assert {:ok, %{validation: validation, row: quoted_row}} =
               Journals.preview_row(c.actor, c.tid, c.bid, request)

      assert quoted_row["credit_total_minor"] ==
               if(direction == "input", do: 112_500, else: 90000)

      assert validation["posting_preview"]["status"] == "complete"

      assert validation["lines"] |> hd() |> get_in(["vat", "posting_vat_minor"]) ==
               if(direction == "input", do: if(share == 0, do: 0, else: 11250), else: 22500)

      if direction == "input",
        do:
          assert(
            hd(validation["posting_preview"]["rows"])["legs"]
            |> Enum.find(&(&1["role"] == "debit"))
            |> Map.get("debit_minor") == amount
          )

      [preview] = validation["posting_preview"]["rows"]
      assert length(preview["legs"]) == leg_count
      cost = Enum.find(preview["legs"], &(&1["role"] == role))
      assert cost[role <> "_minor"] == amount
      assert cost["account"]["id"] == if(role == "credit", do: credit.id, else: debit.id)
      assert cost["non_deductible_vat_minor"] == if(share == 0, do: 22500, else: 11250)
      refute Enum.any?(preview["legs"], &(&1["role"] == "vat_non_deductible"))
    end
  end

  test "income VAT follows credit and reversed income stays on outgoing VAT", c do
    {accounts, _rule, _attrs, income, asset, _command} = posting_setup(c, "output", 0)
    did = create(c)

    for {side, entered, basis, credit, vat, tax_side} <- [
          {"credit", 125_000, "gross", 100_000, -25000, "credit_minor"},
          {"debit", 100_000, "net", 125_000, 25000, "debit_minor"},
          {"debit", -100_000, "net", 125_000, 25000, "debit_minor"}
        ] do
      p = %{
        "id" => nil,
        "reference" => "Income",
        "debit_account_id" => if(side == "debit", do: income.id, else: asset.id),
        "credit_account_id" => if(side == "debit", do: asset.id, else: income.id),
        "amount_minor" => entered,
        "amount_basis" => basis,
        "basis_override" => true,
        "credit_amount_minor" => nil,
        "void" => false
      }

      request = body(c, did, p) |> Map.delete("expected_version")

      assert {:ok, %{row: row, validation: validation}} =
               Journals.preview_row(c.actor, c.tid, c.bid, request)

      assert row["amount_minor"] == abs(entered)
      assert row["credit_total_minor"] == credit
      quote = Enum.find(validation["lines"], & &1["vat"])["vat"]
      assert quote["posting_vat_minor"] == vat
      assert quote["posting_direction"] == "output"
      preview = validation["posting_preview"]
      assert validation["balanced"]
      assert validation["status"] == "prepared"
      assert preview["status"] == "complete"
      assert preview["debit_minor"] == 125_000
      assert preview["credit_minor"] == 125_000
      tax = hd(preview["rows"])["legs"] |> Enum.find(&(&1["role"] == "vat_output"))
      assert tax["account"]["id"] == accounts["output"]
      assert tax[tax_side] == 25000
    end
  end

  test "expense VAT adds to the credit counter account and refund credits reverse input VAT", c do
    {accounts, _rule, _attrs, expense, asset, _command} = posting_setup(c)
    did = create(c)

    for {side, entered, basis, credit, vat} <- [
          {"debit", 50000, "net", 62500, 12500},
          {"credit", 62500, "gross", 50000, -12500}
        ] do
      p = %{
        "id" => nil,
        "reference" => "Expense",
        "debit_account_id" => if(side == "debit", do: expense.id, else: asset.id),
        "credit_account_id" => if(side == "debit", do: asset.id, else: expense.id),
        "amount_minor" => entered,
        "amount_basis" => basis,
        "basis_override" => true,
        "credit_amount_minor" => nil,
        "void" => false
      }

      assert {:ok, %{row: row, validation: validation}} =
               Journals.preview_row(
                 c.actor,
                 c.tid,
                 c.bid,
                 body(c, did, p) |> Map.delete("expected_version")
               )

      assert row["credit_total_minor"] == credit
      quote = Enum.find(validation["lines"], & &1["vat"])["vat"]
      assert quote["posting_vat_minor"] == vat
      preview = validation["posting_preview"]
      assert validation["balanced"]
      assert validation["status"] == "prepared"
      assert preview["status"] == "complete"
      assert preview["debit_minor"] == 62500
      assert preview["credit_minor"] == 62500
      tax = hd(preview["rows"])["legs"] |> Enum.find(&(&1["role"] == "vat_input"))
      assert tax["account"]["id"] == accounts["input"]
      assert tax[if(side == "debit", do: "debit_minor", else: "credit_minor")] == 12500
    end
  end

  test "typed minus signs never swap paired columns even without VAT", c do
    did = create(c)
    p = row(c) |> Map.put("amount_minor", -12500) |> Map.put("credit_amount_minor", -12500)

    assert {:ok, %{row: result, validation: validation}} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, p) |> Map.delete("expected_version")
             )

    assert result["amount_minor"] == 12500
    assert result["credit_total_minor"] == 12500
    [debit, credit] = hd(validation["posting_preview"]["rows"])["legs"]
    assert debit["debit_minor"] == 12500
    assert debit["credit_minor"] == 0
    assert credit["credit_minor"] == 12500
    assert credit["debit_minor"] == 0
    assert validation["posting_preview"]["balanced"]
  end

  test "posting includes generated VAT legs and rejects later deletion", c do
    {_accounts, _rule, _attrs, expense, bank, _command} = posting_setup(c)
    did = create(c)

    p =
      Map.merge(%{"id" => nil, "reference" => "VAT posting", "void" => false}, %{
        "debit_account_id" => expense.id,
        "credit_account_id" => bank.id,
        "amount_minor" => 50000,
        "amount_basis" => "net",
        "vat_enabled" => true,
        "basis_override" => true
      })

    save(c, did, p, "vat-to-post")
    alias Ep.Finance.JournalPosting
    {:ok, impact} = JournalPosting.impact(c.actor, c.tid, c.bid, did)
    assert impact["errors"] == []
    assert Enum.sort(Enum.map(impact["accounts"], & &1["post_minor"])) == [-62500, 12500, 50000]
    attrs = Map.take(impact, ~w(contexts digest draft_id expected_draft_version expected_version))
    assert {:ok, _} = JournalPosting.post(c.actor, c.tid, c.bid, attrs, "post-vat")
    {:ok, _} = JournalProjector.deliver(c.tid)
    {:ok, current} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})

    deletion = %{
      "draft_id" => did,
      "expected_version" => current.latest_version,
      "expected_draft_version" => current.selected["version"],
      "contexts" => current.contexts
    }

    assert {:error, :journal_already_posted} =
             JournalWork.save(c.actor, c.tid, c.bid, "delete", deletion, "delete-posted")

    assert current.selected["data"]["posted"]
  end

  test "apply VAT keeps the entered expense net even when its old account default is gross", c do
    {_accounts, _rule, _attrs, expense, asset, _command} = posting_setup(c)
    did = create(c)

    p = %{
      "id" => nil,
      "reference" => "500 stays 500",
      "debit_account_id" => expense.id,
      "credit_account_id" => asset.id,
      "amount_minor" => 50000,
      "amount_basis" => "gross",
      "basis_override" => true,
      "vat_enabled" => true,
      "credit_amount_minor" => nil,
      "void" => false
    }

    save(c, did, p, "apply-vat-net")
    draft = Repo.get!(JournalDraft, did)
    [saved] = draft.data["rows"]
    assert saved["amount_minor"] == 50000
    assert saved["posting_debit_minor"] == 50000
    assert saved["credit_total_minor"] == 62500
    assert saved["amount_basis"] == "net"
    assert saved["vat_enabled"]
    assert draft.validation["status"] == "prepared"
    [debit, credit, tax] = hd(draft.validation["posting_preview"]["rows"])["legs"]
    assert debit["account"]["id"] == expense.id
    assert debit["debit_minor"] == 50000
    assert credit["credit_minor"] == 62500
    assert tax["debit_minor"] == 12500
    save(c, did, %{p | "id" => saved["id"], "vat_enabled" => false}, "no-vat-net")
    disabled = Repo.get!(JournalDraft, did)
    [row] = disabled.data["rows"]
    assert row["amount_minor"] == 50000
    assert row["credit_total_minor"] == 50000
    assert disabled.validation["status"] == "prepared"
    assert Enum.all?(disabled.validation["lines"], &is_nil(&1["vat"]))
    assert length(hd(disabled.validation["posting_preview"]["rows"])["legs"]) == 2
    assert row["posting_id"] == saved["posting_id"]
  end

  test "apply VAT derives net income from the asset counter amount without a gross checkbox", c do
    {_accounts, _rule, _attrs, income, asset, _command} = posting_setup(c, "output", 0)
    did = create(c)

    p = %{
      "id" => nil,
      "reference" => "Income",
      "debit_account_id" => asset.id,
      "credit_account_id" => income.id,
      "amount_minor" => 125_000,
      "amount_basis" => "net",
      "basis_override" => true,
      "vat_enabled" => true,
      "credit_amount_minor" => nil,
      "void" => false
    }

    assert {:ok, %{row: row, validation: validation}} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, p) |> Map.delete("expected_version")
             )

    assert row["credit_total_minor"] == 100_000
    assert validation["balanced"]
    quote = Enum.find(validation["lines"], & &1["vat"])["vat"]
    assert quote["posting_vat_minor"] == -25000
  end

  test "row VAT override chooses dated settings without changing the account or shared rule", c do
    {_accounts, original, attrs, expense, bank, command} = posting_setup(c)

    alternate =
      Repo.get_by!(Ep.Finance.CatalogueEntry, book_id: c.bid, kind: "vat", code: "output")

    command.(
      "vat_rule_create",
      Map.merge(attrs, %{"vat_entry_id" => alternate.id, "rate_bps" => 1000}),
      "alternate-rate"
    )

    {:ok, _} = SetupProjector.deliver(c.tid)
    did = create(c)

    p = %{
      "id" => nil,
      "reference" => "Override",
      "debit_account_id" => expense.id,
      "credit_account_id" => bank.id,
      "amount_minor" => 50000,
      "amount_basis" => nil,
      "basis_override" => false,
      "vat_enabled" => true,
      "vat_entry_id" => alternate.id,
      "vat_source_side" => "debit",
      "credit_amount_minor" => nil,
      "void" => false
    }

    request = body(c, did, p) |> Map.delete("expected_version")

    assert {:ok, %{row: row, validation: validation, vat_options: options}} =
             Journals.preview_row(c.actor, c.tid, c.bid, request)

    assert row["credit_total_minor"] == 55000
    assert row["amount_minor"] == 50000
    assert validation["status"] == "prepared"
    quote = Enum.find(validation["lines"], & &1["vat"])["vat"]
    assert quote["posting_vat_minor"] == 5000
    assert Enum.any?(options, &(&1.vat_entry_id == alternate.id && &1.rate_bps == 1000))
    assert Repo.get!(Ep.Finance.VatRule, original.id).rate_bps == 2500
    assert Repo.get!(Ep.Finance.Account, expense.id).vat_entry_id == original.vat_entry_id
    save(c, did, p, "save-vat-override")
    [saved] = Repo.get!(JournalDraft, did).data["rows"]
    assert JournalRows.input(saved)["vat_entry_id"] == alternate.id
    assert JournalRows.input(saved)["vat_source_side"] == "debit"
    reverse = %{p | "amount_minor" => 55000, "vat_source_side" => "credit"}

    assert {:ok, %{row: refund, validation: refund_validation}} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, reverse) |> Map.delete("expected_version")
             )

    assert refund["credit_total_minor"] == 50000
    assert refund_validation["status"] == "prepared"
    assert Enum.find(refund_validation["lines"], & &1["vat"])["vat"]["posting_vat_minor"] == -5000

    reset = %{p | "vat_entry_id" => nil, "vat_source_side" => nil}

    assert {:ok, %{row: restored, validation: restored_validation}} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, reset) |> Map.delete("expected_version")
             )

    assert restored["credit_total_minor"] == 62500
    assert restored_validation["status"] == "prepared"

    assert {:error, :invalid_vat_reference} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, %{p | "vat_entry_id" => Ecto.UUID.generate()})
               |> Map.delete("expected_version")
             )

    assert {:error, :invalid_vat_reference} =
             Journals.preview_row(
               c.actor,
               c.tid,
               c.bid,
               body(c, did, %{p | "vat_source_side" => "invalid"})
               |> Map.delete("expected_version")
             )
  end

  test "deleting a journal voids its numbered rows preserves audit and never reuses IDs", c do
    did = create(c)
    save(c, did, row(c), "before-delete")
    old = Repo.one!(JournalRow)
    original = Repo.get!(JournalDraft, did)
    p = body(c, did, row(c, old.id)) |> Map.delete("row")

    assert {:error, :not_found} =
             JournalWork.save(sign_in().principal, c.tid, c.bid, "delete", p, "denied-delete")

    assert {:error, :version_conflict} =
             JournalWork.save(
               c.actor,
               c.tid,
               c.bid,
               "delete",
               Map.put(p, "expected_draft_version", 0),
               "stale-delete"
             )

    assert {:error, :forced} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        JournalWork.save(c.actor, c.tid, c.bid, "delete", p, "rollback-delete")

               Repo.rollback(:forced)
             end)

    refute Repo.get!(JournalDraft, did).data["deleted"]
    refute Repo.get!(JournalRow, old.id).data["void"]
    assert {:ok, result} = JournalWork.save(c.actor, c.tid, c.bid, "delete", p, "delete-journal")

    assert {:ok, %{"replayed" => true}} =
             JournalWork.save(c.actor, c.tid, c.bid, "delete", p, "delete-journal")

    assert Repo.get!(JournalDraft, did).data["deleted"]
    assert Repo.get!(JournalRow, old.id).data["void"]
    assert Repo.get!(JournalCounter, c.bid).last_number == 1
    {:ok, _} = JournalProjector.deliver(c.tid)
    assert {:ok, listing} = Journals.get(c.actor, c.tid, c.bid)
    assert listing.drafts == []
    assert {:error, :not_found} = Journals.get(c.actor, c.tid, c.bid, %{"draft_id" => did})

    assert {:ok, historical} =
             Journals.get(c.actor, c.tid, c.bid, %{
               "draft_id" => did,
               "version" => original.version
             })

    assert hd(historical.selected["data"]["rows"])["posting_id"] == 1

    assert {:error, :not_found} =
             JournalWork.save(
               c.actor,
               c.tid,
               c.bid,
               "row",
               p |> Map.put("row", row(c, old.id)),
               "edit-deleted"
             )

    assert {:ok, :ok} = JournalProjector.rebuild(c.tid)
    assert {:ok, rebuilt} = Journals.get(c.actor, c.tid, c.bid)
    assert rebuilt.drafts == []
    assert rebuilt.source_version == result["stream_version"]
    another = create(c, "after-delete")
    save(c, another, row(c), "new-number")
    assert Repo.get!(JournalCounter, c.bid).last_number == 2
    assert Repo.all(from r in JournalRow, order_by: r.posting_id, select: r.posting_id) == [1, 2]
  end
end
