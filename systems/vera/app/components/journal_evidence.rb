class Components::JournalEvidence < Components::Base
  ERRORS = { "account_required"=>"Select a posting account.", "posting_account_required"=>"Headers and calculations cannot be journal accounts.", "account_inactive_or_retired"=>"The account is inactive or retired.", "choose_one_nonzero_side"=>"Enter a nonzero amount on exactly one side.", "inactive_vat_entry"=>"The selected VAT entry is inactive.", "vat_rule_missing"=>"No active VAT rule covers this date.", "invalid_amount"=>"Enter a signed whole-minor-unit VAT base; assessed overrides apply only to import statements.", "assessment_required"=>"Enter the signed VAT amount from the import statement.", "journal_unbalanced"=>"Debit and credit totals differ.", "two_nonzero_lines_required"=>"The journal needs at least two lines and a nonzero total.", "period_not_open"=>"The posting date is not in an open period.", "account_vat_not_selected"=>"This account has a VAT selection; confirm the explicit no-VAT choice or select a rule." }.freeze
  def initialize(data:)
    @data = data
  end
  def self.status(data)
    return "Updating…" unless data["status"] == "ready"
    return "Posted · Authorized and verified" if data.dig("selected", "data", "posted")
    validation = data.dig("selected", "validation")
    return "Draft" unless validation
    validation["status"] == "prepared" ? "Saved draft · Checks passed at review" : "Saved draft · Needs attention"
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Journal validation and saved status" }
    div(class: "mt-4 space-y-3 text-sm text-amber-900") do
      p(class: "text-xs text-stone-500") { "Draft view #{@data['source_version']} · Latest accepted #{@data['latest_version']} · Book #{@data['book_status']} · #{@data['accounting_authority']} accounting" }
      p { "A draft, setup or period view is updating. Refresh before preparing another review." } unless @data["status"] == "ready"
      p { "Account, VAT or period configuration changed. Save uses a fresh validation; previous evidence stays in History." } if @data["validation_stale"]
      validation = @data.dig("selected", "validation")
      if validation
        p { @data.dig("selected", "data", "posted") ? "Posted · Authorized and verified" : validation["status"] == "prepared" ? "Saved draft · Checks passed at review" : "Saved draft · Needs attention" }
        Array(validation["errors"]).each { |error| p { ERRORS.fetch(error, error.tr("_", " ")) } }
        Array(validation["lines"]).each do |line|
          Array(line["errors"]).each { |error| p { "Line #{line['id']} · #{ERRORS.fetch(error, error.tr('_', ' '))}" } }
        end
      end
    end
  end
end
