class Components::JournalPostingPreview < Components::Base
  def initialize(preview:, separator:, historical: false)
    @preview, @separator, @historical = preview, separator, historical
  end
  def view_template
    details(id: "journal-posting-preview", class: "mt-6 rounded-lg border border-stone-200 bg-white p-4") do
      summary(class: "cursor-pointer font-semibold text-teal-900") { "Saved posting preview · Unposted" }
      p(class: "mt-3 text-sm text-stone-600") { @historical ? "Saved evidence for this revision. Later configuration changes do not alter these amounts or accounts." : "Save row edits to refresh this preview. Authorization, verification and final posting are separate steps." }
      unless @preview
        p(class: "mt-3 text-sm") { "Save a row to build the complete posting preview." }
        return
      end
      p(class: "mt-3 font-medium") { @preview["status"] == "complete" ? "Complete and balanced preview" : "Resolve the preview issues before posting" }
      (Array(@preview["errors"]) - Array(@preview["rows"]).flat_map { |row| Array(row["errors"]) }).each { |error| p(role: "status", class: "mt-2 text-sm text-amber-900") { error_message(error) } }
      Array(@preview["rows"]).each do |row|
        h3(class: "mt-4 font-semibold") { "ID #{row['posting_id']}" }
        Array(row["errors"]).each { |error| p(role: "status", class: "mt-2 text-sm text-amber-900") { error_message(error) } }
        if row["vat_rule"]
          p(class: "mt-1 text-xs text-stone-500") { "VAT rule #{row['vat_rule']['rule_id']} · Revision #{row['vat_rule']['rule_version']} · #{row['vat_rule']['date']}" }
        end
        div(class: "overflow-x-auto") do
          table(class: "mt-3 w-full text-sm") do
            thead { tr { [ "Component", "Account", "Debit", "Credit" ].each_with_index { |text, index| th(class: index>1 ? "p-2 text-right" : "p-2 text-left") { text } } } }
            tbody do
              row.fetch("legs").each do |leg|
                tr(class: "border-t border-stone-100") do
                  td(class: "p-2") { { "debit"=>"Debit account", "credit"=>"Credit account", "vat_input"=>"Incoming VAT", "vat_output"=>"Outgoing VAT", "vat_non_deductible"=>"Non-deductible VAT" }.fetch(leg["role"], leg["role"].tr("_", " ")) }
                  td(class: "p-2", title: leg["account"] && "Account #{leg['account']['id']} · Revision #{leg['account']['version']}") do
                    plain(leg["account"] ? "#{leg['account']['number']} · #{leg['account']['name']}" : "Unavailable account")
                    p(class: "mt-1 text-xs text-stone-500") { "Includes #{money(leg['non_deductible_vat_minor'])} non-deductible VAT" } if leg["non_deductible_vat_minor"]
                  end
                  td(class: "p-2 text-right tabular-nums") { money(leg["debit_minor"]) }
                  td(class: "p-2 text-right tabular-nums") { money(leg["credit_minor"]) }
                end
              end
            end
          end
        end
      end
      p(class: "mt-4 text-right text-sm font-semibold") { "Debit #{money(@preview['debit_minor'])} · Credit #{money(@preview['credit_minor'])} · Difference #{money(@preview['difference_minor'])}" }
    end
  end
  def error_message(error)
    code, role=error.split(":", 2)
    title={ "input"=>"incoming VAT", "output"=>"outgoing VAT", "non_deductible"=>"non-deductible VAT", "vat_input"=>"incoming VAT", "vat_output"=>"outgoing VAT", "vat_non_deductible"=>"non-deductible VAT" }[role] || role
    case code
    when "vat_posting_account_missing" then "Choose the #{title} posting account in the VAT rule."
    when "posting_account_unavailable" then "The #{title} posting account is missing, inactive or retired."
    when "multiple_vat_accounts" then "Both accounts have VAT configured. Select a single VAT source for this row."
    when "posting_preview_unbalanced" then "The posting legs do not balance. Check the amounts and VAT mappings."
    when "empty_journal" then "Enter at least one complete journal line."
    when "debit_account_required" then "Choose a debit posting account."
    when "credit_account_required" then "Choose a credit posting account."
    else error.tr("_", " ")
    end
  end
  def money(amount) = JournalMoney.format(amount, separator: @separator)
end
