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
    get path, params: { vat_entry_id: VID }
    assert_response :success
    assert_select "details[data-vat-advanced]:not([open]) select[name='posting_accounts[non_deductible]'] option[value='']", text: "Follow expense/asset account (default)"
    assert_select "details[data-vat-advanced]:not([open]) input[name='mappings[][box]']", count: 4
    assert_select "select[name=direction] option[value='']", text: "Choose treatment"
    assert_select "input[name=rate][value='']"
    command = stub_request(:post, api).with(body: attrs).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: form(token)
    assert_redirected_to "#{path}?vat_entry_id=#{VID}#vat-code-#{VID}"
    assert_requested command
  end
  test "book VAT posting accounts are explicit configuration in the original command" do
    options=[ { id: RID, number: "6900", name: "Incoming VAT", active: true } ]
    view(data.merge(posting_accounts: options))
    get path, params: { vat_entry_id: VID }
    assert_select "select[name='posting_accounts[input]'] option[value='#{RID}']"
    assert_select "select[name='posting_accounts[output]']"
    command=stub_request(:post, api).with(body: attrs.merge(posting_accounts: { input: RID, output: nil, non_deductible: nil })).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: form(token).merge(posting_accounts: { input: RID, output: "", non_deductible: "" })
    assert_redirected_to "#{path}?vat_entry_id=#{VID}#vat-code-#{VID}"
    assert_requested command
  end
  test "overlap conflicts preserve the valid draft and require explicit reapplication" do
    view
    get path, params: { vat_entry_id: VID }
    t = token
    stub_request(:post, api).to_return(status: 409, body: { error: "vat_rule_overlap" }.to_json)
    patch path, params: form(t)
    assert_response :conflict
    assert_select "input[name=rate][value='25.50']"
    assert_select "input[name=deductible][value='25.00']"
    assert_includes response.body, "date ranges"
    assert_select "input[value='Reapply settings draft']"
  end
  test "unknown acceptance keeps its original body/key through receipt check and explicit retry" do
    view
    get path, params: { vat_entry_id: VID }
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
    assert_redirected_to "#{path}?vat_entry_id=#{VID}#vat-code-#{VID}"
    assert_requested command, times: 2
  end
  test "read-only/pending states suppress forms and revoked access clears rule data" do
    view(data.merge(permissions: { configure: false }))
    get path, params: { vat_entry_id: VID }
    assert_select "input[name=form_token]", count: 0
    view(data.merge(status: "pending", latest_version: 3))
    get path, params: { vat_entry_id: VID }
    assert_select "input[name=form_token]", count: 0
    stub_request(:get, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    get path, params: { vat_entry_id: VID }
    assert_response :not_found
    assert_not_includes response.body, "Input VAT"
  end
  test "the largest reporting draft retains original-request recovery in the encrypted session" do
    view
    get path, params: { vat_entry_id: VID }
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
    assert_select "#choose-vat-preset select[name=preset_id] option[value=REP]"
    assert_select "details[data-vat-advanced]:not([open]) input[value='Købsmoms']"
    expected = attrs.merge(rate_bps: 2500, assessment_basis: "net", preset_id: "REP", preset_version: preset[:version], mappings: preset[:mappings])
    command = stub_request(:post, api).with(body: expected).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: form(token).merge(rate: "25", assessment_basis: "net", preset_id: "REP", preset_version: preset[:version], mappings: preset[:mappings])
    assert_redirected_to "#{path}?vat_entry_id=#{VID}#vat-code-#{VID}"
    assert_requested command
    get path, params: { preset_id: "REP", preset_version: "obsolete" }
    assert_response :unprocessable_entity
    assert_includes response.body, "preset version is unavailable"
  end
  def dated_settings(id, first, last = nil)
    { id: id, vat_entry_id: VID, valid_from: first, valid_until: last, direction: "input", rate_bps: 2500, deductible_bps: 10000, active: true, version: 1, posting_accounts: {}, mappings: { lines: [] } }
  end
  test "codes group current scheduled and earlier settings by the selected date" do
    view(data.merge(vat_entries: data[:vat_entries] + [ { id: "unconfigured", code: "Other", name: "Other VAT", active: true } ], vat_rules: [ dated_settings("old", "2025-01-01", "2025-12-31"), dated_settings(RID, "2026-01-01", "2026-12-31"), dated_settings("future", "2027-01-01") ]))
    get path, params: { as_of: "2026-06-01", vat_entry_id: VID }
    assert_response :success
    assert_select "#vat-code-#{VID} [data-vat-settings='Current settings']", count: 1
    assert_select "#vat-code-#{VID} [data-vat-settings='Scheduled change']", count: 1
    assert_select "#vat-code-#{VID} details [data-vat-settings='Earlier settings']", count: 1
    assert_select "#vat-code-row-unconfigured td", text: "Not configured"
  end
  test "scheduling copies settings into a new draft bound to the same code with blank dates" do
    view(data.merge(vat_rules: [ dated_settings(RID, "2026-01-01") ]))
    get path, params: { vat_entry_id: VID, copy_from: RID }
    assert_response :success
    assert_select "#vat_rule_create-new select[name=vat_entry_id][disabled]"
    assert_select "#vat_rule_create-new input[name=vat_entry_id][value='#{VID}']"
    assert_select "#vat_rule_create-new input[name=rate][value='25.00']"
    assert_select "#vat_rule_create-new input[name=valid_from][value]", count: 0
    assert_select "#vat_rule_create-new input[name=rule_id]", count: 0
    assert_not_requested :post, api
  end
  test "invalid settings dates and foreign code contexts do not write configuration" do
    view
    get path, params: { as_of: "2026-02-30" }
    assert_response :unprocessable_entity
    assert_includes response.body, "Choose a valid settings date"
    get path, params: { vat_entry_id: RID }
    assert_response :not_found
    assert_not_requested :post, api
  end
  test "index shows one compact row per code and no settings forms or history" do
    view(data.merge(vat_rules: [ dated_settings(RID, "2026-01-01") ]))
    get path, params: { as_of: "2026-06-01" }
    assert_response :success
    assert_select "tbody tr[data-vat-code-row]", count: 1
    assert_select "#open-vat-code-#{VID}[data-turbo-stream]"
    assert_select "tbody td", text: "Configured"
    assert_select "#vera-book-content input[name=form_token]", count: 0
    assert_select "[data-vat-settings], #shared-content-dialog", count: 0
    assert_not_includes response.body, "Revision history"
  end
  test "row link streams only the selected code into the shared dialog" do
    view(data.merge(vat_entries: data[:vat_entries] + [ { id: RID, code: "Other", name: "Other VAT", active: true } ], vat_rules: [ dated_settings(RID, "2026-01-01") ]))
    get path, params: { vat_entry_id: VID, as_of: "2026-06-01" }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] template dialog#shared-content-dialog", count: 1
    assert_select "#shared-dialog-title", text: "Input · Input VAT"
    assert_select "#shared-content-dialog [data-vat-code='#{RID}']", count: 0
    assert_select "#shared-content-dialog [data-vat-settings='Current settings']", count: 1
    assert_select "#vera-book-content [data-vat-settings]", count: 0
    assert_select "#shared-content-dialog form[data-turbo-stream]"
  end
  test "streamed save refreshes the list and selected dialog while conflicts retain the draft" do
    view
    get path, params: { vat_entry_id: VID }
    t = token
    stub_request(:post, api).to_return(status: 409, body: { error: "vat_rule_overlap" }.to_json)
    patch path, params: form(t), as: :turbo_stream
    assert_response :conflict
    assert_select "turbo-stream[target=shared-dialog-host] #shared-content-dialog input[name=rate][value='25.50']"
    t = token
    stub_request(:post, api).to_return(status: 200, body: { stream_version: 3 }.to_json)
    view(data.merge(source_version: 3, latest_version: 3, vat_rules: [ dated_settings(RID, "2026-01-01") ]))
    patch path, params: form(t).merge(as_of: "2026-06-01"), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='vat-code-row-#{VID}'] #vat-code-row-#{VID} td", text: "Configured"
    assert_select "turbo-stream[target=shared-dialog-host] [data-vat-settings='Current settings']"
    assert_select "#shared-content-dialog [role=alert]", text: /Setup accepted/
  end
  test "revoked access clears an open VAT dialog and list" do
    stub_request(:get, api).to_return(status: 403, body: { error: "forbidden" }.to_json)
    get path, params: { vat_entry_id: VID }, as: :turbo_stream
    assert_response :forbidden
    assert_select "turbo-stream[target=shared-dialog-host] template", text: ""
    assert_select "turbo-stream[target=vera-book-content]"
    assert_not_includes response.body, "Input VAT"
  end
  test "accepted changes wait for the projected revision then replace only their index row" do
    view
    get path, params: { vat_entry_id: VID }
    t = token
    command = stub_request(:post, api).to_return(status: 200, body: { stream_version: 3 }.to_json)
    view(data.merge(status: "pending", latest_version: 3))
    patch path, params: form(t).merge(as_of: "2026-06-01"), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='vat-code-row-#{VID}']", count: 0
    assert_select "turbo-stream[target='vat-refresh-#{VID}'] vat-index-refresh", count: 1
    refresh_url = css_select("vat-index-refresh").first["data-url"]
    get refresh_url, as: :turbo_stream
    assert_response :success
    assert_select "vat-index-refresh", count: 1
    view(data.merge(source_version: 3, latest_version: 3, vat_rules: [ dated_settings(RID, "2026-01-01") ]))
    get refresh_url, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='vat-code-row-#{VID}'] td", text: "25,00%"
    assert_select "turbo-stream[target=vera-book-content], turbo-stream[target=shared-dialog-host], vat-index-refresh", count: 0
    assert_requested command, times: 1
    get refresh_url.sub(BID, RID), as: :turbo_stream
    assert_response :unprocessable_entity
    assert_not_requested :get, api.sub(BID, RID)
  end
  test "a ready projection older than the accepted revision keeps waiting" do
    ticket = Rails.application.message_verifier(:vat_row_refresh).generate({ scope: "#{TID}/#{BID}", entry_id: VID, as_of: "2026-06-01", version: 3 }, purpose: :vat_row_refresh, expires_in: 1.hour)
    view
    get "#{path}/refresh_row", params: { ticket: ticket }, as: :turbo_stream
    assert_response :success
    assert_select "vat-index-refresh", count: 1
    assert_select "turbo-stream[target='vat-code-row-#{VID}']", count: 0
    stub_request(:get, api).to_return(status: 403, body: { error: "forbidden" }.to_json)
    get "#{path}/refresh_row", params: { ticket: ticket }, as: :turbo_stream
    assert_response :forbidden
    assert_select "turbo-stream[target=vera-book-content]"
    assert_select "turbo-stream[target=shared-dialog-host]"
  end
end
