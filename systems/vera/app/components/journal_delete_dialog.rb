class Components::JournalDeleteDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(data:, token:)
    @data, @token = data, token
  end
  def view_template
    draft = @data.fetch("selected")
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Delete journal?" }
    p(class: "mt-4 font-medium") { "#{draft.dig('data', 'name')} · #{draft.dig('data', 'posting_date')}" }
    p(class: "mt-3 text-sm text-stone-600") { "The journal will leave the journal list. Its numbered postings will be voided; posting IDs, history and enclosures remain for traceability. Unsaved edits will be discarded." }
    form_with(url: tenant_book_journals_path(@data["tenant_id"], @data["book_id"]), method: :patch, data: { turbo: false }) do |f|
      f.hidden_field(:form_token, value: @token)
      f.hidden_field(:expected_version, value: @data["latest_version"])
      f.hidden_field(:expected_draft_version, value: draft["version"])
      f.hidden_field(:draft_id, value: draft["id"])
      @data.fetch("contexts").each { |key, value| input(type: "hidden", name: "contexts[#{key}]", value: value) }
      f.submit("Delete journal", class: "mt-5 cursor-pointer rounded bg-red-800 px-5 py-3 font-semibold text-white hover:bg-red-700")
    end
  end
end
