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
               put_in(b, ["row", "amount_minor"], -1),
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

    p = body(c, did, row(c)) |> Map.delete("expected_version")
    assert {:ok, %{row: %{"posting_id" => nil}}} = Journals.preview_row(c.actor, c.tid, c.bid, p)
    assert Repo.aggregate(JournalRow, :count) == 0
    assert Repo.get!(JournalCounter, c.bid).last_number == 0
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
end
