class Components::Catalogues < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(data:, token:, draft: nil, message: nil, check_url: nil, retry_url: nil)
    @data, @token, @draft, @message, @check, @retry = data, token, draft, message, check_url, retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @ready = data["status"] == "ready" && !check_url
    @configure = @ready && data.dig("permissions", "configure")
  end
  def view_template
    div(id: "vera-book-content", class: "break-words") do
      a(href: tenant_book_setup_path(@tid, @bid), class: "text-sm font-medium text-teal-900 hover:underline") { "← Roles and occasions" }
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      div(class: "mt-3 flex flex-wrap items-end justify-between gap-4") do
        h1(class: "text-3xl font-semibold tracking-tight") { "VAT and category catalogues" }
        a(href: tenant_book_chart_path(@tid, @bid), class: "text-sm font-medium text-teal-900 hover:underline") { "Chart of accounts" }
      end
      p(class: "mt-4 max-w-3xl text-sm leading-relaxed text-stone-600") { "Manage classification labels for this book. Accounts keep stable references when codes or names change. Inactive entries remain on existing accounts but cannot be selected for new associations." }
      p(class: "mt-3 text-xs text-stone-500") { "VAT entries are setup labels. Tax rates, calculations and posting rules are configured in later work." }
      p(role: "alert", class: "mt-5 rounded-lg bg-amber-50 p-4 text-sm") { @message } if @message
      if @check
        a(href: @check, data: { turbo_stream: true }, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      p(role: "status", class: "mt-5 rounded-lg bg-amber-50 p-4 text-sm") { "The catalogue view is updating. Refresh before making another change." } unless @data["status"] == "ready"
      p(class: "mt-4 text-xs text-stone-500") { "View revision #{@data['source_version']} · Latest accepted #{@data['latest_version']}" }
      a(href: tenant_book_catalogues_path(@tid, @bid), class: "mt-3 inline-block text-sm font-medium text-teal-900 hover:underline") { "Refresh catalogues" }
      if @draft && !@configure
        h2(class: "mt-6 text-lg font-semibold") { "Your submitted draft" }
        pre(class: "mt-3 whitespace-pre-wrap rounded-lg bg-amber-50 p-4 text-sm") { @draft.fetch(:attrs).except(:expected_version, :expected_entry_version).map { |key, value| "#{key}: #{value}" }.join("\n") }
      end
      unless @data["catalogues_initialized"]
        section(class: "mt-7 rounded-xl border border-stone-200 bg-white p-6") do
          h2(class: "text-xl font-semibold") { "Initialize this book’s catalogues" }
          p(class: "mt-3 text-sm leading-relaxed text-stone-600") { "Adopt the existing three VAT and five category labels as editable entries. Existing account selections are bound to stable IDs in one accepted batch; their meaning and earlier history are preserved." }
          command_form("catalogue_initialize") { |f| f.submit("Initialize catalogues", class: BUTTON) } if @configure
        end
        return
      end
      [ [ "vat", "VAT entries" ], [ "category", "Categories" ] ].each do |kind, title|
        section(class: "mt-9", aria_label: title) do
          h2(class: "text-xl font-semibold") { title }
          @data.fetch("catalogue_entries").select { |entry| entry["kind"] == kind }.each { |entry| entry_card(entry) }
        end
      end
      if @configure
        h2(class: "mt-9 text-xl font-semibold") { "Add an entry" }
        entry_form(nil)
      end
    end
  end
  private
  def draft_for(action, id = nil)
    @draft && @draft[:action] == action && @draft.dig(:attrs, :entry_id) == id ? @draft.fetch(:attrs) : nil
  end
  def command_form(action, entry = nil)
    form_with(url: tenant_book_catalogues_path(@tid, @bid), method: :patch, namespace: "#{action}-#{entry && entry['id'] || 'new'}", id: "#{action}-#{entry && entry['id'] || 'new'}", class: "mt-4") do |f|
      f.hidden_field(:form_token, value: @token.call(action, entry && entry.fetch("id")))
      f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
      f.hidden_field(:expected_entry_version, value: entry.fetch("version")) if entry
      yield f
    end
  end
  def entry_card(entry)
    div(id: "catalogue-#{entry.fetch('id')}", class: "mt-4 rounded-xl border border-stone-200 bg-white p-5") do
      draft = draft_for("catalogue_revise", entry["id"])
      entry_form(entry) if draft && @configure
      h3(class: "text-lg font-semibold") { "#{entry['code']} · #{entry['name']}" }
      p(class: "mt-2 text-xs text-stone-500") { "#{entry['active'] ? 'Active' : 'Inactive'} · Revision #{entry['version']}" }
      if @configure && !draft
        details(class: "mt-4") do
          summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Edit entry" }
          entry_form(entry)
        end
      end
      details(class: "mt-4 border-t border-stone-200 pt-3") do
        summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Entry history (#{entry.fetch('history', []).length})" }
        ol(class: "mt-3 space-y-3") do
          entry.fetch("history", []).reverse_each do |fact|
            li(class: "rounded-lg bg-stone-50 p-3 text-sm") do
              p { "#{fact['code']} · #{fact['name']} · #{fact['active'] ? 'Active' : 'Inactive'} · Revision #{fact['version']}" }
              p(class: "mt-2 text-xs text-stone-500") { "#{fact['accepted_at']} · Actor #{fact['actor_identity_id']} · Application #{fact['application_id']}" }
            end
          end
        end
      end
    end
  end
  def entry_form(entry)
    action = entry ? "catalogue_revise" : "catalogue_create"
    draft = draft_for(action, entry && entry["id"])
    values = draft ? draft.stringify_keys : entry || {}
    command_form(action, entry) do |f|
      p(class: "mb-3 text-sm font-semibold text-amber-900") { "Your submitted draft — compare with the accepted entry below" } if draft
      div(class: "grid gap-4 md:grid-cols-3") do
        unless entry
          div do
            f.label(:kind, "Catalogue", class: "text-sm font-medium")
            f.select(:kind, [ [ "VAT", "vat" ], [ "Category", "category" ] ], { selected: values["kind"] }, class: FIELD)
          end
        end
        div do
          f.label(:code, "Code", class: "text-sm font-medium")
          f.text_field(:code, value: values["code"], required: true, maxlength: 120, class: FIELD)
        end
        div do
          f.label(:name, "Name", class: "text-sm font-medium")
          f.text_field(:name, value: values["name"], required: true, maxlength: 120, class: FIELD)
        end
        if entry
          div do
            f.label(:active, "Status", class: "text-sm font-medium")
            f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: values["active"].to_s }, class: FIELD)
          end
        end
      end
      f.submit(draft ? "Reapply entry draft" : entry ? "Save entry" : "Create entry", class: BUTTON)
      a(href: tenant_book_catalogues_path(@tid, @bid), class: "ml-4 text-sm font-medium text-teal-900 hover:underline") { "Cancel" }
    end
  end
end
