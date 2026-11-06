class Components::JournalDetailsDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(data:, token:, values: nil, message: nil)
    @data, @token, @values, @message = data, token, values, message
  end
  def view_template
    draft = @data.fetch("selected")
    values = @values || draft.fetch("data")
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Edit journal details" }
    p(role: "alert", class: "mt-3 rounded bg-amber-50 p-3 text-sm") { @message } if @message
    form_with(url: tenant_book_journals_path(@data["tenant_id"], @data["book_id"]), method: :patch, data: { turbo: false, journal_details: true }, class: "mt-4") do |f|
      f.hidden_field(:form_token, value: @token)
      f.hidden_field(:draft_id, value: draft["id"])
      f.hidden_field(:expected_draft_version, value: draft["version"])
      f.hidden_field(:expected_version, value: @data["latest_version"])
      @data.fetch("contexts").each { |key, value| input(type: "hidden", name: "contexts[#{key}]", value: value) }
      div(class: "grid gap-4 sm:grid-cols-2") do
        div(class: "sm:col-span-2") { f.label(:name, "Draft name"); f.text_field(:name, value: values["name"], required: true, maxlength: 120, class: Views::Base::FIELD) }
        div { f.label(:posting_date, "Posting date"); f.date_field(:posting_date, value: values["posting_date"], required: true, class: Views::Base::FIELD) }
        div { f.label(:reference, "Reference"); f.text_field(:reference, value: values["reference"], maxlength: 120, class: Views::Base::FIELD) }
      end
      f.submit("Save journal details", class: Views::Base::BUTTON)
    end
  end
end
