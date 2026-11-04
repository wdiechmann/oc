defmodule Ep.Finance.VatRulesTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, CatalogueEntry, Setup, SetupProjector, VatRule, VatRules}

  setup do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "VAT"}, "tenant")
    tid = t["tenant_id"]

    {:ok, book} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "VAT",
          "code" => "VAT",
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
        "init"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    entry = Repo.get_by!(CatalogueEntry, book_id: bid, kind: "vat", code: "input")
    %{actor: owner.principal, tid: tid, bid: bid, entry: entry.id}
  end

  defp attrs(c, changes \\ %{}),
    do:
      Map.merge(
        %{
          "vat_entry_id" => c.entry,
          "valid_from" => "2026-01-01",
          "valid_until" => "2026-12-31",
          "direction" => "input",
          "rate_bps" => 2500,
          "deductible_bps" => 2500,
          "mappings" => [%{"box" => "Input VAT", "component" => "deductible_vat", "sign" => 1}],
          "expected_version" => 2
        },
        changes
      )

  defp create(c, p \\ nil, key \\ "rule"),
    do: Setup.command(c.actor, c.tid, c.bid, "vat_rule_create", p || attrs(c), key)

  test "labels do not infer rates; inclusive effective ranges select exact accepted versions",
       c do
    assert {:ok, %{vat_rules: []}} = VatRules.get(c.actor, c.tid, c.bid)

    assert {:error, :vat_rule_missing} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-01-01", 10000)

    {:ok, first} = create(c)

    assert {:error, :vat_rule_overlap} =
             create(
               c,
               attrs(c, %{
                 "valid_from" => "2026-12-31",
                 "valid_until" => nil,
                 "expected_version" => 3
               }),
               "overlap"
             )

    {:ok, second} =
      create(
        c,
        attrs(c, %{
          "valid_from" => "2027-01-01",
          "valid_until" => nil,
          "rate_bps" => 2000,
          "deductible_bps" => 10000,
          "expected_version" => 3
        }),
        "next"
      )

    {:ok, q} = VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-12-31", 10000)
    assert q.rule_id == hd(first["event_ids"])
    assert q.rule_version == 3

    assert q.amounts == %{
             "net" => 10000,
             "vat" => 2500,
             "deductible_vat" => 625,
             "non_deductible_vat" => 1875
           }

    assert q.reporting == %{"Input VAT" => 625}
    assert q.invoice_total_minor == 12500

    assert {:error, :invalid_amount} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-12-31", 10000, 2500)

    {:ok, q} = VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2027-01-01", 10000)
    assert q.rule_id == hd(second["event_ids"])
    assert q.amounts["vat"] == 2000

    assert {:error, :vat_rule_missing} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2025-12-31", 10000)
  end

  test "revisions retain immutable rule history through ordinary setup updates and rebuild", c do
    {:ok, r} = create(c)
    id = hd(r["event_ids"])
    {:ok, _} = SetupProjector.deliver(c.tid)

    p =
      attrs(c, %{
        "rule_id" => id,
        "active" => true,
        "expected_rule_version" => 3,
        "expected_version" => 3,
        "rate_bps" => 1500
      })

    {:ok, _} = Setup.command(c.actor, c.tid, c.bid, "vat_rule_revise", p, "revise")

    assert {:error, :version_conflict} =
             Setup.command(
               c.actor,
               c.tid,
               c.bid,
               "vat_rule_revise",
               %{p | "expected_version" => 4},
               "stale"
             )

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "catalogue_create",
        %{"kind" => "category", "code" => "Other", "name" => "Other", "expected_version" => 4},
        "other"
      )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, before} = VatRules.get(c.actor, c.tid, c.bid)
    rule = hd(before.vat_rules)
    assert Enum.map(rule["history"], & &1["rate_bps"]) == [2500, 1500]
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, after_rebuild} = VatRules.get(c.actor, c.tid, c.bid)
    assert before.vat_rules == after_rebuild.vat_rules
    original = Repo.get!(Ep.Events.Details, id).payload["setup"]["vat_rules"] |> hd()
    assert original["rate_bps"] == 2500
    assert Repo.get!(VatRule, id).rate_bps == 1500
  end

  test "fractional deduction, credits and reverse charge use exact signed integer rounding", c do
    {:ok, _} =
      create(
        c,
        attrs(c, %{
          "direction" => "reverse_charge",
          "deductible_bps" => 5000,
          "mappings" => [
            %{"box" => "Both", "component" => "net", "sign" => 1},
            %{"box" => "Both", "component" => "vat", "sign" => 1},
            %{"box" => "Deduction", "component" => "deductible_vat", "sign" => -1}
          ]
        })
      )

    {:ok, pos} = VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", 2)
    {:ok, neg} = VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", -2)
    assert pos.amounts["vat"] == 1 && pos.amounts["deductible_vat"] == 1
    assert neg.amounts["vat"] == -1 && neg.amounts["deductible_vat"] == -1
    assert pos.invoice_total_minor == 2 && neg.invoice_total_minor == -2
    assert pos.reporting == %{"Both" => 3, "Deduction" => -1}

    assert {:error, :invalid_amount} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", 1.5)
  end

  test "date, type, percentage, mapping and cross-catalogue guards reject invalid rules", c do
    category = Repo.get_by!(CatalogueEntry, book_id: c.bid, kind: "category", code: "assets")

    for changed <- [
          %{"vat_entry_id" => category.id},
          %{"vat_entry_id" => Ecto.UUID.generate()},
          %{"valid_from" => "2026-2-01"},
          %{"valid_until" => "2025-12-31"},
          %{"rate_bps" => 10001},
          %{"rate_bps" => 25.5},
          %{"deductible_bps" => -1},
          %{"direction" => "output"},
          %{"direction" => "none"},
          %{"mappings" => [%{"box" => "X", "component" => "unknown", "sign" => 1}]},
          %{"mappings" => List.duplicate(%{"box" => "X", "component" => "vat", "sign" => 1}, 2)}
        ] do
      assert {:error, _} = create(c, attrs(c, changed), Ecto.UUID.generate())
    end

    assert Repo.aggregate(VatRule, :count) == 0

    assert {:ok, _} =
             create(
               c,
               attrs(c, %{
                 "direction" => "none",
                 "rate_bps" => 0,
                 "deductible_bps" => 0,
                 "mappings" => []
               })
             )
  end

  test "current stewardship precedes replay and inactive VAT/rules cannot resolve", c do
    {:ok, created} = create(c)
    assert {:ok, %{"replayed" => true}} = create(c)
    id = hd(created["event_ids"])

    p =
      attrs(c, %{
        "rule_id" => id,
        "active" => false,
        "expected_rule_version" => 3,
        "expected_version" => 3
      })

    {:ok, _} = Setup.command(c.actor, c.tid, c.bid, "vat_rule_revise", p, "deactivate")

    assert {:error, :vat_rule_missing} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-01-01", 10000)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => false, "expected_version" => 4},
        "revoke"
      )

    assert {:error, :not_found} = create(c)
    assert {:error, :not_found} = VatRules.get(sign_in().principal, c.tid, c.bid)
    assert_raise RuntimeError, fn -> VatRules.lock_rule!(c.tid, c.bid, c.entry, "2026-01-01") end
  end

  test "inactive VAT entries retain history but cannot be used for new rules or calculations",
       c do
    {:ok, _} = create(c)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "catalogue_revise",
        %{
          "entry_id" => c.entry,
          "code" => "input",
          "name" => "Input VAT",
          "active" => false,
          "expected_version" => 3,
          "expected_entry_version" => 2
        },
        "inactive-entry"
      )

    assert {:error, :inactive_catalogue_entry} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", 10000)

    assert {:error, :inactive_catalogue_entry} =
             create(
               c,
               attrs(c, %{
                 "expected_version" => 4,
                 "valid_from" => "2027-01-01",
                 "valid_until" => nil
               }),
               "new"
             )

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, data} = VatRules.get(c.actor, c.tid, c.bid)
    assert length(hd(data.vat_rules)["history"]) == 1
  end

  test "Danish presets remain drafts and pin reviewed provenance", c do
    alias Ep.Finance.DanishVatPresets
    presets = DanishVatPresets.all()
    assert length(presets) == 16
    assert length(Enum.uniq_by(presets, & &1["id"])) == 16
    assert {:ok, %{presets: ^presets, vat_rules: []}} = VatRules.get(c.actor, c.tid, c.bid)

    for preset <- presets do
      assert Enum.all?(preset["sources"], &String.starts_with?(&1, "https://"))

      p =
        attrs(
          c,
          Map.merge(
            Map.take(preset, ~w(direction rate_bps deductible_bps mappings assessment_basis)),
            %{"preset_id" => preset["id"], "preset_version" => preset["version"]}
          )
        )

      # Validate every template without retaining overlapping rules.
      assert {:error, :verified} =
               Repo.transaction(fn ->
                 assert {:ok, result} = create(c, p, preset["id"])
                 rule = Repo.get!(VatRule, hd(result["event_ids"]))
                 assert rule.preset["customized"] == false
                 assert rule.preset["baseline"]["mappings"] == preset["mappings"]
                 Repo.rollback(:verified)
               end)
    end

    rep = DanishVatPresets.find("REP", "2026-11-04.1")
    assert rep["deductible_bps"] == 2500
    assert DanishVatPresets.find("HOTEL", rep["version"])["deductible_bps"] == 10000

    assert DanishVatPresets.suggested_entries(DanishVatPresets.find("UEUV", rep["version"]), [
             %{"code" => "UEUV2 - Other", "active" => true},
             %{"code" => "UEUV - EU goods", "active" => true},
             %{"code" => "UEUV", "active" => false}
           ]) == [%{"code" => "UEUV - EU goods", "active" => true}]

    assert {:error, :invalid_vat_preset} =
             create(c, attrs(c, %{"preset_id" => "REP", "preset_version" => "obsolete"}))

    {:ok, r} =
      create(
        c,
        attrs(c, %{"preset_id" => "REP", "preset_version" => rep["version"], "rate_bps" => 2000})
      )

    id = hd(r["event_ids"])
    assert Repo.get!(VatRule, id).preset["customized"]

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "vat_rule_revise",
        attrs(c, %{
          "rule_id" => id,
          "expected_version" => 3,
          "expected_rule_version" => 3,
          "active" => true,
          "mappings" => rep["mappings"]
        }),
        "preserve-origin"
      )

    assert Repo.get!(VatRule, id).preset["id"] == "REP"
    assert Repo.get!(VatRule, id).preset["customized"] == false

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, before} = VatRules.get(c.actor, c.tid, c.bid)
    assert hd(hd(before.vat_rules)["history"])["preset"]["id"] == "REP"
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, rebuilt} = VatRules.get(c.actor, c.tid, c.bid)
    assert before.vat_rules == rebuilt.vat_rules
  end

  test "import statements require an explicit signed assessed VAT amount", c do
    p = Ep.Finance.DanishVatPresets.find("IVV", "2026-11-04.1")

    {:ok, _} =
      create(
        c,
        attrs(c, Map.take(p, ~w(direction rate_bps deductible_bps mappings assessment_basis)))
      )

    assert {:error, :assessment_required} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", 10000)

    assert {:error, :assessment_required} =
             VatRules.quote(c.actor, c.tid, c.bid, c.entry, "2026-06-01", 10000, -3275)

    for sign <- [1, -1] do
      assert {:ok, quote} =
               VatRules.quote(
                 c.actor,
                 c.tid,
                 c.bid,
                 c.entry,
                 "2026-06-01",
                 sign * 10000,
                 sign * 3275
               )

      assert quote.amounts["vat"] == sign * 3275
      assert quote.amounts["deductible_vat"] == sign * 3275
      assert quote.invoice_total_minor == sign * 10000
    end
  end
end
