require "test_helper"

class ChartAccountsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  AID = "bd763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept"=>"text/vnd.turbo-stream.html" }
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/chart"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup"
  def data
    { tenant_id: TID, book_id: BID, book_name: "SL2030", catalogues_initialized: true, status: "ready", source_version: 2, latest_version: 2, pagination: { page: 1, per_page: 50, total_entries: 1, total_pages: 1 }, options: { vat_codes: [ { id: TID, kind: "vat", code: "input", name: "Input VAT", active: true } ], categories: [ { id: BID, kind: "category", code: "assets", name: "Assets", active: true } ] }, permissions: { assign_stewards: true, configure: true }, stewards: [], candidates: [ { identity_id: AID, label: "steward@example.test" } ], occasions: [ { occasion_id: AID, name: "Camp" } ], bindings: [], accounts: [ { id: AID, number: "0010", name: "Bank", kind: "posting", position: 100, vat_code: "none", category: "assets", formula: nil, active: true, version: 2, actor_identity_id: AID, application_id: "vera" } ] }
  end
  def view(payload = data)
    stub_request(:get, %r{#{Regexp.escape(api)}/accounts(?:\?.*)?\z}).to_return(status: 200, body: payload.to_json)
  end
  def token(action, id = "new")
    css_select("#setup-#{action}-#{id} input[name=form_token]").first["value"]
  end
  def draft(form_token)
    { form_token: form_token, expected_version: "2", expected_account_version: "2", number: "0010", name: "My draft", kind: "posting", active: "true", position: "100", vat_code: "none", category: "assets" }
  end

  test "setup forms preserve number strings and use signed scoped command keys" do
    view
    get path
    assert_response :success
    assert_select "input[name=number][value='0010']"
    assert_select "header h1", text: "Chart of accounts"
    assert_select "#chart-header-actions [role=menuitem]", text: "Refresh chart"
    assert_select "#chart-header-actions [role=menuitem]", text: "Import CSV"
    assert_select "#chart-header-actions [data-chart-export]", text: "Export accepted chart"
    assert_select "coa-editor [data-chart-export]", count: 0
    create = stub_request(:post, "#{api}/accounts").with(body: { expected_version: 2, number: "0020", name: "Cash", kind: "posting", position: 200, vat_code: nil, category: nil, formula: nil }, headers: { "Idempotency-Key"=>/\A[0-9a-f-]{36}\z/ }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("account_create"), expected_version: "2", number: "0020", name: "Cash", kind: "posting", position: "200" }
    assert_redirected_to path
    assert_requested create
  end

  test "conflict keeps the user draft above the newer accepted row and requires explicit reapplication" do
    view
    get path
    form_token = token("account_revise", AID)
    revised = data
    revised[:accounts][0].merge!(name: "Newer accepted", version: 3)
    revised.merge!(source_version: 3, latest_version: 3)
    view(revised)
    update = stub_request(:patch, "#{api}/accounts/#{AID}").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch path, params: draft(form_token), headers: STREAM
    assert_response :conflict
    assert_select "turbo-stream[target=vera-book-content]"
    assert_select "input[name=name][value='My draft']"
    assert_select ".coa-conflict", text: /Newer accepted/
    assert_includes response.body, "Reapply"
    assert_select "input[name=expected_account_version][value='3']"
    assert_operator response.body.index("My draft"), :<, response.body.index("coa-conflict")
    assert_requested update, times: 1
  end

  test "unknown saves block further mutations and receipt recovery never repeats a save" do
    view
    get path
    form_token = token("account_revise", AID)
    update = stub_request(:patch, "#{api}/accounts/#{AID}").to_timeout
    patch path, params: draft(form_token), headers: STREAM
    assert_response :service_unavailable
    assert_select "a", text: "Check completion"
    patch path, params: draft(form_token), headers: STREAM
    assert_requested update, times: 1
    get path
    assert_select "input[name=form_token]", count: 0
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceSetup:account_revise", idempotency_key: Rails.application.message_verifier(:finance_setup).verified(form_token, purpose: :finance_setup).fetch("key") }).to_return(status: 200, body: { status: "accepted", result: { book_id: BID } }.to_json)
    get "#{path}/completion"
    assert_redirected_to "#{path}?focus_id=#{AID}"
    assert_requested update, times: 1
  end

  test "an explicit retry after an unknown receipt uses the unchanged original body and key" do
    view
    get path
    form_token = token("account_revise", AID)
    original_key = Rails.application.message_verifier(:finance_setup).verified(form_token, purpose: :finance_setup).fetch("key")
    update = stub_request(:patch, "#{api}/accounts/#{AID}").with(headers: { "Idempotency-Key"=>original_key }, body: { expected_version: 2, expected_account_version: 2, number: "0010", name: "My draft", kind: "posting", active: true, position: 100, vat_code: "none", category: "assets", formula: nil }).to_timeout
    patch path, params: draft(form_token), headers: STREAM
    post "#{path}/retry", headers: STREAM
    assert_response :unprocessable_entity
    assert_requested update, times: 1
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceSetup:account_revise", idempotency_key: original_key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion", headers: STREAM
    assert_select "input[type=submit][value='Retry original request']"
    assert_requested update, times: 1
    update.to_return(status: 200, body: { stream_version: 3 }.to_json)
    post "#{path}/retry", params: { name: "Tampered replacement" }
    assert_redirected_to "#{path}?focus_id=#{AID}"
    assert_requested update, times: 2
  end

  test "revocation clears protected streamed content and cannot be bypassed by a signed stale form" do
    view
    get path
    form_token = token("account_revise", AID)
    stub_request(:patch, "#{api}/accounts/#{AID}").to_return(status: 404, body: { error: "not_found" }.to_json)
    patch path, params: draft(form_token), headers: STREAM
    assert_response :not_found
    assert_select "turbo-stream[target=vera-book-content]"
    assert_not_includes response.body, "My draft"
  end

  test "inspection without stewardship and pending views expose no account mutation forms" do
    view(data.merge(permissions: { assign_stewards: true, configure: false }))
    get path
    assert_select "#setup-steward-new", count: 0
    assert_select "#setup-account_create-new", count: 0
    assert_select "#setup-binding-new", count: 0
    view(data.merge(status: "pending", latest_version: 3))
    get path
    assert_select "input[name=form_token]", count: 0
    assert_includes response.body, "view is updating"
  end

  test "the chart has seven ordered columns and setup links to it without embedding account forms" do
    view
    get path
    assert_select "[role=columnheader]", text: /Type|Number|Name|VAT|Category|Position|Formula|Actions/, count: 8
    assert_equal %w[Type Number Name VAT Category Position Formula Actions], css_select("[role=columnheader]").map(&:text)
    assert_select "coa-editor [data-coa-row]", count: 2
    assert_select "select[name=kind] option[value=header]"
    assert_select "select[name=kind] option[value=calculation]"
    assert_select "textarea[name=formula]"
    stub_request(:get, api).to_return(status: 200, body: data.to_json)
    get "/tenants/#{TID}/books/#{BID}/setup"
    assert_select "a[href='#{path}']", text: "Open chart of accounts"
    assert_select "input[name=number]", count: 0
    assert_select "#setup-steward-new"
  end

  test "paginated streams append only the requested page and replace pagination controls" do
    next_page = data.merge(pagination: { page: 2, per_page: 50, total_entries: 120, total_pages: 3 })
    view(next_page)
    get path, params: { page: "2", source_version: "2", append: "1" }, headers: STREAM
    assert_response :success
    assert_select "turbo-stream[action=append][target=coa-rows]"
    assert_select "turbo-stream[action=replace][target=coa-pagination]"
    assert_select "turbo-stream[target=vera-book-content]", count: 0
    assert_select "a[data-coa-next][href*='page=3']"
    get path, params: { page: "2" }
    assert_response :success
    assert_select "nav[aria-label='Chart pages'] a[href*='page=3']"
  end

  test "changed snapshots stop infinite append without discarding the existing editor" do
    stub_request(:get, %r{#{Regexp.escape(api)}/accounts(?:\?.*)?\z}).to_return(status: 409, body: { error: "chart_changed" }.to_json)
    get path, params: { page: "2", source_version: "1", append: "1" }, headers: STREAM
    assert_response :conflict
    assert_select "turbo-stream[target=vera-feedback]"
    assert_select "turbo-stream[target=coa-rows]", count: 0
    assert_select "turbo-stream[target=vera-book-content]", count: 0
  end

  test "header and calculation saves send position and formula without requiring a posting number" do
    view
    get path
    header = stub_request(:post, "#{api}/accounts").with(body: { expected_version: 2, number: nil, name: "Assets", kind: "header", position: 200, vat_code: nil, category: nil, formula: nil }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("account_create"), expected_version: "2", name: "Assets", kind: "header", position: "200" }
    assert_response :see_other
    assert_requested header
    get path
    calculation = stub_request(:post, "#{api}/accounts").with(body: { expected_version: 2, number: nil, name: "Total", kind: "calculation", position: 300, vat_code: nil, category: nil, formula: "[0010] * 2" }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("account_create"), expected_version: "2", name: "Total", kind: "calculation", position: "300", formula: "[0010] * 2" }
    assert_response :see_other
    assert_requested calculation
  end

  test "tampered forms never reach EP" do
    view
    get path
    patch path, params: draft("tampered"), headers: STREAM
    assert_response :unprocessable_entity
    assert_not_requested :patch, "#{api}/accounts/#{AID}"
  end
  test "retired accounts are read-only and history navigation retains its scope" do
    retired = data.merge(retired: true, permissions: { configure: false, assign_stewards: true }, pagination: { page: 1, per_page: 50, total_entries: 60, total_pages: 2 })
    view(retired)
    get path, params: { retired: "1" }
    assert_response :success
    assert_select "h1", text: "Retired accounts"
    assert_select "input[name=form_token]", count: 0
    assert_select "input[name=retired][value='1']"
    assert_select "a[data-coa-next][href*='retired=1']"
    assert_select "a[data-chart-export]", count: 0
    assert_select "a", text: "Current chart"
  end
  test "replacement by another steward preserves a draft for an account no longer in the current chart" do
    view
    get path
    form_token = token("account_revise", AID)
    view(data.merge(accounts: [], source_version: 5, latest_version: 5, pagination: { page: 1, per_page: 50, total_entries: 0, total_pages: 1 }))
    stub_request(:patch, "#{api}/accounts/#{AID}").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch path, params: draft(form_token)
    assert_response :conflict
    assert_includes response.body, "no longer in the current chart"
    assert_select "pre", text: /My draft/
    assert_select "input[value=Reapply]", count: 0
  end
end
