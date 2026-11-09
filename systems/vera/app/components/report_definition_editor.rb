class Components::ReportDefinitionEditor < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :report_definition_editor
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(data:, values:, extra_line: false)
    @data, @values, @extra = data, values, extra_line
  end
  def view_template
    lines = @values.fetch("lines", []).dup
    lines << { "position" => (lines.map { |line| line["position"].to_i }.max || 0) + 100, "kind" => "mapping", "sign" => 1 } if lines.empty? || @extra
    accounts = (Array(@data.dig("selected", "definition", "accounts")) + @data.fetch("accounts")).index_by { |a| a["id"] }
    report_definition_editor(class: "mt-6 block", data: { dialog_url: line_dialog_tenant_book_reports_path(@data["tenant_id"], @data["book_id"]) }) do
      p(class: "text-sm text-stone-600") { "Select a line to edit it. Changes stay in this draft until you review and accept the complete report." }
      p(data: { report_editor_error: true }, role: "status", class: "mt-2 text-sm text-amber-900")
      form_with(url: review_tenant_book_reports_path(@data["tenant_id"], @data["book_id"]), method: :post, id: "report-editor", data: { turbo: false }) do |f|
        f.hidden_field(:expected_version, value: @values["expected_version"] || @data["latest_version"])
        f.hidden_field(:report_type, value: @values["report_type"]) if @values["report_type"].present?
        f.hidden_field(:report_id, value: @values["report_id"])
        f.hidden_field(:expected_report_version, value: @values["expected_report_version"])
        div(class: "grid gap-4 sm:grid-cols-2") do
          div { f.label(:name, "Report name"); f.text_field(:name, value: @values["name"], maxlength: 120, required: true, class: FIELD) }
          div { f.label(:active, "Status"); f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: @values["active"].to_s }, class: FIELD) }
        end
        div(class: "mt-4 overflow-x-auto rounded-lg border border-stone-200") do
          table(class: "w-full text-left text-sm") do
            thead(class: "bg-stone-100") { tr { [ "Type", "Code", "Name", "Position", "Sign", "Accounts / Formula", "" ].each { |label| th(scope: "col", class: "px-3 py-2") { label } } } }
            tbody do
              lines.first(2000).each_with_index do |line, index|
                tr(class: "border-t border-stone-200 hover:bg-teal-50", data: { report_line: index }) do
                  td(class: "px-3 py-2") do
                    span(data: { line_summary: "kind" }) { line["kind"] || "mapping" }
                    span(data: { line_inputs: true }, hidden: true) do
                      %w[id code name kind position sign formula remove].each { |key| input(type: "hidden", name: "lines[#{index}][#{key}]", value: line[key]) }
                      Array(line["account_ids"]).each { |id| input(type: "hidden", name: "lines[#{index}][account_ids][]", value: id, data: { account_label: accounts[id] ? "#{accounts[id]['number']} · #{accounts[id]['name']}" : id }) }
                    end
                  end
                  td(class: "px-3 py-2", data: { line_summary: "code" }) { line["code"] }
                  td(class: "px-3 py-2") { button(type: "button", id: "report-line-#{index}", data: { edit_report_line: index, line_summary: "name" }, class: "text-left font-medium text-teal-900 underline") { line["name"].presence || "New line" } }
                  td(class: "px-3 py-2", data: { line_summary: "position" }) { line["position"] }
                  td(class: "px-3 py-2", data: { line_summary: "sign" }) { line["kind"] == "mapping" ? (line["sign"] == -1 ? "−" : "+") : "" }
                  td(class: "px-3 py-2", data: { line_summary: "detail" }) { line["kind"] == "total" ? line["formula"] : Array(line["account_ids"]).map { |id| accounts[id] ? "#{accounts[id]['number']} · #{accounts[id]['name']}" : id }.join("; ") }
                  td(class: "sticky right-0 bg-white px-3 py-2 text-right") do
                    render Components::ContextMenu.new(id: "report-line-actions-#{index}", label: "Actions for report line #{index + 1}") do
                      button(type: "button", role: "menuitem", class: "vera-menu-item", data: { edit_report_line: index }) { "Edit" }
                      button(type: "button", role: "menuitem", class: "vera-menu-item", data: { delete_report_line: index }) { "Delete" }
                    end
                  end
                end
              end
            end
          end
        end
        f.submit("Review report", class: BUTTON)
        button(type: "submit", name: "intent", value: "add_line", class: "ml-4 text-sm text-teal-900 underline", formnovalidate: true) { "Add report line" } if lines.length < 2000
      end
    end
  end
end
