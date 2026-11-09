class Components::ReportLineDeleteDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :report_line_delete_dialog
  def initialize(line:, index:)
    @line, @index = line, index
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Delete report line?" }
    p(class: "mt-4 font-medium") { [ @line["code"], @line["name"].presence || "New line" ].compact.join(" · ") }
    p(class: "mt-3 text-sm text-stone-600") { "This removes the line from your draft. Review and accept the complete report to save the deletion. Update any formulas that reference this line’s code before accepting." }
    report_line_delete_dialog(data: { index: @index }) do
      form_with(url: "#", method: :post, data: { turbo: false }) do |f|
        f.submit("Delete line", class: "mt-5 cursor-pointer rounded bg-red-800 px-5 py-3 font-semibold text-white hover:bg-red-700")
      end
    end
  end
end
