class Components::ChartRow < Components::Base
  include Phlex::Rails::Helpers::FormWith
  KINDS = [ [ "Header", "header" ], [ "Calculation", "calculation" ], [ "Posting", "posting" ] ].freeze
  FIELD = "coa-input"
  def initialize(data:, account:, token:, draft: nil, locked: false)
    @data, @account, @token, @draft, @locked = data, account, token, draft, locked
    @id = account && account.fetch("id")
    @action = account ? "account_revise" : "account_create"
    @draft = nil unless draft && draft[:action] == @action && draft[:attrs][:account_id] == @id
    @values = @draft ? @draft[:attrs].stringify_keys : account || { "kind"=>"posting", "position"=>nil, "active"=>true }
    @editable = data["status"] == "ready" && data["catalogues_initialized"] == true && data.dig("permissions", "configure") && !locked
  end
  def view_template
    div(id: "account-#{@id || 'new'}", role: "row", tabindex: @account ? "0" : "-1", class: "coa-row", data: { coa_row: true, account_id: @id, page: @data.dig("pagination", "page"), draft: (!!@draft).to_s, new_row: (!@account).to_s }) do
      if @account
        div(class: "coa-columns coa-display", data: { coa_display: true }, hidden: !!@draft) do
          cells(@account)
          div(role: "cell") do
            button(type: "button", data: { coa_edit: true }, class: "coa-action") { "Edit" } if @editable
            button(type: "button", data: { coa_reference: @id }, class: "coa-action", title: "Copy a stable formula reference") { "Copy ref" }
            span(class: "text-xs text-stone-400") { @account["retired"] ? "Retired" : "Inactive" } unless @account["active"]
          end
        end
      elsif @editable
        button(type: "button", data: { coa_edit: true, coa_display: true }, hidden: !!@draft, class: "m-3 rounded-lg border border-teal-800 px-4 py-2 text-sm font-medium text-teal-900") { "+ Add row" }
      end
      editor if @editable
      if @draft && @account
        div(class: "coa-conflict") do
          p(class: "px-3 py-2 text-xs font-semibold text-amber-900") { "Newer accepted row · Revision #{@account['version']} · Actor #{@account['actor_identity_id']} · Application #{@account['application_id']}" }
          div(class: "coa-columns") { cells(@account); div(role: "cell") { "Accepted" } }
        end
      end
    end
  end
  private
  def cells(account)
    values = [ account["kind"].to_s.capitalize, account["number"], account["name"], account["vat_label"] || label(account["vat_code"]), account["category_label"] || label(account["category"]), account["position"], account["formula"] ]
    values.each { |value| div(role: "cell", class: "coa-cell", title: value.to_s) { value.to_s } }
  end
  def label(value) = value.to_s.tr("_", " ").capitalize
  def editor
    form_with(url: tenant_book_chart_path(@data.fetch("tenant_id"), @data.fetch("book_id")), method: :patch, id: "setup-#{@action}-#{@id || 'new'}", namespace: "account-#{@id || 'new'}", class: "coa-editor-form", html: { hidden: !@draft }, data: { coa_form: true }) do |f|
      f.hidden_field(:form_token, value: @token.call(@action, @id))
      f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
      f.hidden_field(:expected_account_version, value: @account.fetch("version")) if @account
      p(class: "px-3 py-2 text-xs font-semibold text-amber-900") { "Your draft — compare with the accepted row below" } if @draft
      div(class: "coa-columns") do
        div(role: "cell") { f.label(:kind, "Type", class: "sr-only"); f.select(:kind, KINDS, { selected: @values["kind"] }, class: FIELD, data: { coa_kind: true }) }
        text_field(f, :number, "Number", kinds: "posting", maxlength: 40, pattern: "[A-Za-z0-9](?:[A-Za-z0-9._]|-){0,39}")
        text_field(f, :name, "Name", maxlength: 120)
        dropdown(f, :vat_entry_id, "VAT", @data.dig("options", "vat_codes") || [])
        dropdown(f, :category_entry_id, "Category", @data.dig("options", "categories") || [])
        div(role: "cell") do
          f.label(:position, "Position", class: "sr-only")
          f.number_field(:position, value: @values["position"], min: 1, max: 2_147_483_647, required: true, class: FIELD)
        end
        div(role: "cell", data: { coa_kinds: "calculation" }) do
          f.label(:formula, "Formula", class: "sr-only")
          f.text_area(:formula, value: @values["formula"], rows: 1, maxlength: 2000, placeholder: "[0010] + [0020]", class: FIELD, title: "Arithmetic with [account-number] or [@account-id], e.g. [0010] + [0020]")
        end
        div(role: "cell", class: "coa-actions") do
          f.submit(@draft ? "Reapply" : "Save", class: "coa-action coa-save")
          button(type: "button", data: { coa_cancel: true }, class: "coa-action") { "Cancel" }
          if @account
            f.label(:active, "Active", class: "sr-only")
            f.select(:active, [ [ "Active", "true" ], [ "Inactive", "false" ] ], { selected: @values["active"].to_s }, class: "coa-input coa-lifecycle")
          end
        end
      end
    end
  end
  def text_field(f, name, label, kinds: nil, **attrs)
    div(role: "cell", data: { coa_kinds: kinds }) do
      f.label(name, label, class: "sr-only")
      f.text_field(name, value: @values[name.to_s], required: true, class: FIELD, **attrs)
    end
  end
  def dropdown(f, name, title, values)
    div(role: "cell", data: { coa_kinds: "posting" }) do
      f.label(name, title, class: "sr-only")
      selected = @values[name.to_s]
      choices = values.filter_map do |value|
        if value.is_a?(Hash)
          next unless value["active"] || value["id"] == selected
          [ "#{value['code']} · #{value['name']}#{value['active'] ? '' : ' (inactive)'}", value.fetch("id") ]
        end
      end
      f.select(name, choices, { selected: selected, include_blank: "—" }, class: FIELD)
    end
  end
end
