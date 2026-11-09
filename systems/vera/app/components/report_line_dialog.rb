class Components::ReportLineDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :report_line_dialog
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(line:, index:, accounts:)
    @line, @index, @accounts = line, index, accounts
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Edit report line" }
    report_line_dialog(data: { index: @index }) do
      form_with(url: "#", method: :post, id: "report-line-dialog-form", data: { turbo: false }) do |f|
        f.hidden_field(:id, value: @line["id"])
        %w[code name position].each do |field|
          f.label(field, field.capitalize, class: "mt-3 block text-sm")
          if field == "position"
            f.number_field(field, value: @line[field], min: 1, max: 2_000_000_000, required: true, class: FIELD)
          else
            f.text_field(field, value: @line[field], maxlength: field == "code" ? 40 : 120, required: true, class: FIELD)
          end
        end
        f.label(:kind, "Type", class: "mt-3 block text-sm")
        f.select(:kind, [ [ "Mapping", "mapping" ], [ "Total", "total" ], [ "Header", "header" ] ], { selected: @line["kind"].presence || "mapping" }, class: FIELD)
        div(data: { report_kind: "mapping" }) do
          f.label(:sign, "Mapping sign", class: "mt-3 block text-sm")
          f.select(:sign, [ [ "+ Add balances", "1" ], [ "− Subtract balances", "-1" ] ], { selected: (@line["sign"] || 1).to_s }, class: FIELD)
          f.label(:account_ids, "Posting accounts", class: "mt-3 block text-sm")
          f.select(:account_ids, @accounts.map { |a| [ "#{a['number']} · #{a['name']}", a["id"] ] } + (Array(@line["account_ids"]) - @accounts.map { |a| a["id"] }).map { |id| [ "Unavailable / retired: #{id} — clear before review", id ] }, { selected: Array(@line["account_ids"]) }, multiple: true, size: 8, class: FIELD)
        end
        div(data: { report_kind: "total" }) do
          f.label(:formula, "Total formula", class: "mt-3 block text-sm")
          f.text_area(:formula, value: @line["formula"], maxlength: 2000, class: FIELD)
          p(class: "mt-2 text-xs text-stone-500") { "Reference report line codes in brackets, for example [REVENUE] - [COSTS]." }
        end
        f.submit("Apply to draft", class: BUTTON)
        p(class: "mt-2 text-xs text-stone-500") { "Review and accept the complete report to save these changes." }
      end
    end
  end
end
