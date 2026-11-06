require "test_helper"

class EnclosureSuggestionsTest < ActiveSupport::TestCase
  test "Danish invoice labels produce exact net VAT and total with source evidence" do
    text = "Leverandør: Dansk Leverandør ApS\nFaktura nr: INV-001\nFakturadato: 06.11.2026\nForfaldsdato: 20.11.2026\nSubtotal 1.000,00 DKK\nMoms 25% 250,00 DKK\nI alt 1.250,00 DKK\nCVR: 12345678"
    fields = EnclosureSuggestions.call(text).index_by { |field| field["key"] }
    assert_equal 125000, fields.fetch("total")["value"]
    assert_equal 25000, fields.fetch("vat")["value"]
    assert_equal 100000, fields.fetch("net")["value"]
    assert_equal "Dansk Leverandør ApS", fields.fetch("supplier")["value"]
    assert_equal "INV-001", fields.fetch("invoice_number")["value"]
    assert_equal "2026-11-06", fields.fetch("date")["value"]
    assert_equal "2026-11-20", fields.fetch("due_date")["value"]
    assert_equal "DKK", fields.fetch("currency")["value"]
    assert_equal "12345678", fields.fetch("vat_number")["value"]
    assert_equal "Moms 25% 250,00 DKK", fields.fetch("vat")["source"]
  end
  test "English grouped decimals and negative credit note totals stay exact" do
    fields = EnclosureSuggestions.call("Supplier: Example Ltd\nNet total 1,000.00\nVAT amount 25% 250.00\nGrand total -1,250.00 GBP")
    assert_equal [ -125000 ], fields.select { |f| f["key"] == "total" }.map { |f| f["value"] }
    assert_equal [ 25000 ], fields.select { |f| f["key"] == "vat" }.map { |f| f["value"] }
  end
  test "percentages and VAT identifiers do not become VAT amounts" do
    fields = EnclosureSuggestions.call("VAT 25%\nVAT number: DK12345678\nTotal incl VAT 1.250,00 DKK")
    assert_empty fields.select { |f| f["key"] == "vat" }
    assert_equal 125000, fields.find { |f| f["key"] == "total" }["value"]
  end
  test "conflicting totals remain separate candidates and invalid dates are omitted" do
    fields = EnclosureSuggestions.call("Total 125,00\nTotal 150,00\nInvoice date 31.02.2026")
    totals = fields.select { |f| f["key"] == "total" }
    assert_equal [ 12500, 15000 ], totals.map { |f| f["value"] }
    assert totals.all? { |f| f["label"] == "Total candidate" }
    assert_empty fields.select { |f| f["key"] == "date" }
  end
end
