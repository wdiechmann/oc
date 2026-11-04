require "test_helper"

class VatRulesTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  VID = "ad763842-2538-4ccb-8445-17e232c37d84"
  RID = "bd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/vat_rules"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/vat-rules"
  def data
    { tenant_id: TID, book_id: BID, book_name: "Rules", source_version: 2, latest_version: 2, status: "ready", catalogues_initialized: true, permissions: { configure: true }, vat_entries: [ { id: VID, code: "Input", name: "Input VAT", active: true } ], vat_rules: [] }
  end
  def view(d = data)
    stub_request(:get, api).to_return(status: 200, body: d.to_json)
  end
  def token
    css_select("#vat_rule_create-new input[name=form_token]").first["value"]
  end
  def form(t)
    { form_token: t, expected_version: "2", vat_entry_id: VID, valid_from: "2026-01-01", valid_until: "2026-12-31", direction: "input", rate: "25.50", deductible: "25", mappings: [ { box: "Input VAT", component: "deductible_vat", sign: "1" }, { box: "", component: "", sign: "1" } ] }
  end
  def attrs
    { expected_version: 2, vat_entry_id: VID, valid_from: "2026-01-01", valid_until: "2026-12-31", direction: "input", rate_bps: 2550, deductible_bps: 2500, mappings: [ { box: "Input VAT", component: "deductible_vat", sign: 1 } ] }
  end
  test "explicit percentages and reporting mappings are sent as exact integer configuration" do
    view
    get path
    assert_response :success
    assert_select "select[name=direction] option[value='']", text: "Choose treatment"
    assert_select "input[name=rate][value='']"
    command = stub_request(:post, api).with(body: attrs).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: form(token)
    assert_redirected_to path
    assert_requested command
  end
  test "overlap conflicts preserve the valid draft and require explicit reapplication" do
    view
    get path
    t = token
    stub_request(:post, api).to_return(status: 409, body: { error: "vat_rule_overlap" }.to_json)
    patch path, params: form(t)
    assert_response :conflict
    assert_select "input[name=rate][value='25.50']"
    assert_select "input[name=deductible][value='25.00']"
    assert_includes response.body, "date ranges"
    assert_select "input[value='Reapply rule draft']"
  end
  test "unknown acceptance keeps its original body/key through receipt check and explicit retry" do
    view
    get path
    t = token
    key = Rails.application.message_verifier(:finance_setup).verified(t, purpose: :finance_setup).fetch("key")
    command = stub_request(:post, api).with(body: attrs, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: form(t)
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    patch path, params: form(t)
    assert_requested command, times: 1
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceSetup:vat_rule_create", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    assert_select "form[action='#{path}/retry']"
    command.to_return(status: 200, body: { stream_version: 3 }.to_json)
    post "#{path}/retry", params: { rate: "99" }
    assert_redirected_to path
    assert_requested command, times: 2
  end
  test "read-only/pending states suppress forms and revoked access clears rule data" do
    view(data.merge(permissions: { configure: false }))
    get path
    assert_select "input[name=form_token]", count: 0
    view(data.merge(status: "pending", latest_version: 3))
    get path
    assert_select "input[name=form_token]", count: 0
    stub_request(:get, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    get path
    assert_response :not_found
    assert_not_includes response.body, "Input VAT"
  end
  test "the largest reporting draft retains original-request recovery in the encrypted session" do
    view
    get path
    t = token
    mappings = [ [ "<"*60, "net" ], [ "&"*60, "vat" ], [ "æ"*60, "deductible_vat" ], [ "🧾"*60, "non_deductible_vat" ] ].map { |box, component| { box: box, component: component, sign: "1" } }
    stub_request(:post, api).to_timeout
    patch path, params: form(t).merge(mappings: mappings, assessment_basis: "net", preset_id: "UEUV2", preset_version: "2026-11-04.1")
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
  end
  test "Danish preset selection creates only an editable draft with blank dates" do
    preset = { id: "REP", version: "2026-11-04.1", checked_on: "2026-11-04", title: "Restaurant", aliases: [ "REP" ], direction: "input", rate_bps: 2500, deductible_bps: 2500, assessment_basis: "net", mappings: [ { box: "Købsmoms", component: "deductible_vat", sign: 1 } ], conditions: "Eligible restaurant expenditure only", sources: [ "https://skat.dk/erhverv/moms" ] }
    view(data.merge(presets: [ preset ], vat_entries: [ { id: VID, code: "REP - Restaurant", name: "Restaurant", active: true } ]))
    get path, params: { preset_id: "REP", preset_version: preset[:version] }
    assert_response :success
    assert_select "#vat_rule_create-new input[name=preset_id][value=REP]"
    assert_select "#vat_rule_create-new input[name=valid_from][value]", count: 0
    assert_select "#vat_rule_create-new option[value='#{VID}'][selected]"
    assert_select "#vat_rule_create-new input[name=deductible][value='25.00']"
    expected = attrs.merge(rate_bps: 2500, assessment_basis: "net", preset_id: "REP", preset_version: preset[:version], mappings: preset[:mappings])
    command = stub_request(:post, api).with(body: expected).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: form(token).merge(rate: "25", assessment_basis: "net", preset_id: "REP", preset_version: preset[:version], mappings: preset[:mappings])
    assert_redirected_to path
    assert_requested command
    get path, params: { preset_id: "REP", preset_version: "obsolete" }
    assert_response :unprocessable_entity
    assert_includes response.body, "preset version is unavailable"
  end
end
