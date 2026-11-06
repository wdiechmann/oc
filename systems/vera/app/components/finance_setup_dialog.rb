class Components::FinanceSetupDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  TITLES = { "steward"=>"Steward assignment", "reopening_authority"=>"Permission to reopen periods", "binding"=>"Link occasion" }.freeze
  def initialize(data:, kind:, token:, values: nil)
    @data, @kind, @token, @values = data, kind, token, values || {}
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { TITLES.fetch(@kind) }
    form_with(url: tenant_book_setup_path(@data["tenant_id"], @data["book_id"]), method: :patch, namespace: "#{@kind}-new", id: "setup-#{@kind}-new", data: { turbo: false }, class: "mt-4") do |f|
      f.hidden_field(:form_token, value: @token)
      f.hidden_field(:expected_version, value: @data.fetch("latest_version"))
      case @kind
      when "steward"
        choices = @data.fetch("candidates").map { |c| [ c.fetch("label"), c.fetch("identity_id") ] }
        choices += @data.fetch("stewards").reject { |s| choices.any? { |c| c.last == s["identity_id"] } }.map { |s| [ s.fetch("identity_id"), s.fetch("identity_id") ] }
        select_field(f, :identity_id, "Existing identity", choices)
        select_field(f, :active, "Role action", [ [ "Assign steward", "true" ], [ "Revoke steward", "false" ] ])
        f.submit("Save steward assignment", class: BUTTON)
      when "reopening_authority"
        p(class: "text-sm font-medium") { "Separate permission to reopen closed periods" }
        choices = @data.fetch("stewards").map do |s|
          candidate = @data.fetch("candidates").find { |c| c["identity_id"] == s["identity_id"] }
          [ candidate ? candidate.fetch("label") : s.fetch("identity_id"), s.fetch("identity_id") ]
        end
        select_field(f, :identity_id, "Assigned steward", choices)
        select_field(f, :allow, "Reopening permission", [ [ "Grant reopening permission", "true" ], [ "Revoke reopening permission", "false" ] ])
        f.submit("Save reopening permission", class: BUTTON)
      when "binding"
        select_field(f, :occasion_id, "Occasion", @data.fetch("occasions").map { |o| [ o.fetch("name"), o.fetch("occasion_id") ] })
        select_field(f, :active, "Binding action", [ [ "Link to this book", "true" ], [ "Unlink from this book", "false" ] ])
        p(class: "mt-3 text-xs text-stone-500") { "Each occasion has one applicable book. Its current book’s steward must unlink it before reassignment." }
        f.submit("Save occasion binding", class: BUTTON)
      end
    end
  end
  def select_field(f, name, label, choices)
    f.label(name, label, class: "mt-3 block text-sm font-medium")
    value = @values.key?(name) ? @values[name] : @values[name.to_s]
    f.select(name, choices, value.nil? ? {} : { selected: value.to_s }, required: true, class: FIELD)
  end
end
