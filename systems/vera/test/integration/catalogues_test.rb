require "test_helper"
class CataloguesTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  EID = "bd763842-2538-4ccb-8445-17e232c37d84"
  OTHER = "ad763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept"=>"text/vnd.turbo-stream.html" }
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "catalogue-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/catalogues"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup/catalogues"
  def data(initialized = true)
    { tenant_id: TID, book_id: BID, book_name: "SL2030", status: "ready", source_version: 2, latest_version: 2, catalogues_initialized: initialized, permissions: { configure: true }, catalogue_entries: initialized ? [ { id: EID, kind: "vat", code: "input", name: "Input VAT", active: true, version: 2, history: [ { code: "input", name: "Input VAT", active: true, version: 2, actor_identity_id: EID, application_id: "vera", accepted_at: "2026-11-02T16:00:00Z" } ] } ] : [] }
  end
  def view(payload = data) = stub_request(:get, api).to_return(status: 200, body: payload.to_json)
  def token(action, id = "new") = css_select("##{action}-#{id} input[name=form_token]").first["value"]
  test "book initialization is explicit and signed without silently seeding on reads" do
    view(data(false))
    get path
    assert_response :success
    assert_select "input[value='Initialize catalogues']"
    initialize = stub_request(:post, "#{api}/initialize").with(body: { expected_version: 2 }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("catalogue_initialize"), expected_version: "2" }
    assert_redirected_to path
    assert_requested initialize, times: 1
  end
  test "create and revise entries preserve signed identity, versions and lifecycle status" do
    view
    get path
    assert_select "#catalogue-#{EID}"
    assert_includes response.body, "Entry history"
    create = stub_request(:post, api).with(body: { expected_version: 2, code: "NEW", name: "New category", kind: "category" }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("catalogue_create"), expected_version: "2", kind: "category", code: "NEW", name: "New category" }
    assert_redirected_to path
    assert_requested create
    get path
    revise = stub_request(:patch, "#{api}/#{EID}").with(body: { expected_version: 2, expected_entry_version: 2, code: "BUY", name: "Purchases", active: false }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("catalogue_revise", EID), expected_version: "2", expected_entry_version: "2", code: "BUY", name: "Purchases", active: "false", entry_id: OTHER }
    assert_redirected_to path
    assert_requested revise
  end
  test "conflicts keep a draft above the newer accepted entry with current versions" do
    view
    get path
    key = token("catalogue_revise", EID)
    newer = data
    newer[:catalogue_entries][0].merge!(name: "Newer accepted", version: 3)
    newer.merge!(source_version: 3, latest_version: 3)
    view(newer)
    stub_request(:patch, "#{api}/#{EID}").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_entry_version: "2", code: "MY", name: "My draft", active: "true" }, headers: STREAM
    assert_response :conflict
    assert_select "input[name=name][value='My draft']"
    assert_select "input[name=expected_entry_version][value='3']"
    assert_operator response.body.index("My draft"), :<, response.body.index("Newer accepted")
  end
  test "lost entry responses reconcile the original receipt without replaying the save" do
    view
    get path
    key = token("catalogue_revise", EID)
    command_key = Rails.application.message_verifier(:finance_setup).verified(key, purpose: :finance_setup).fetch("key")
    save = stub_request(:patch, "#{api}/#{EID}").to_timeout
    patch path, params: { form_token: key, expected_version: "2", expected_entry_version: "2", code: "MY", name: "My draft", active: "true" }, headers: STREAM
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']", text: "Check completion"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceSetup:catalogue_revise", idempotency_key: command_key }).to_return(status: 200, body: { status: "accepted", result: { entry_id: EID } }.to_json)
    get "#{path}/completion"
    assert_redirected_to path
    assert_requested save, times: 1
  end
  test "pending/readonly views cannot edit and access loss clears protected entries" do
    view(data.merge(status: "pending", latest_version: 3))
    get path
    assert_select "input[name=form_token]", count: 0
    view(data.merge(permissions: { configure: false }))
    get path
    assert_select "input[name=form_token]", count: 0
    view
    get path
    key = token("catalogue_revise", EID)
    stub_request(:patch, "#{api}/#{EID}").to_return(status: 404, body: { error: "not_found" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_entry_version: "2", code: "MY", name: "My draft", active: "true" }, headers: STREAM
    assert_response :not_found
    assert_select "turbo-stream[target=vera-book-content]"
    assert_not_includes response.body, "Input VAT"
  end
  test "chart dropdowns use stable IDs and retain only their own inactive associations" do
    options = [ { "id"=>EID, "kind"=>"vat", "code"=>"OLD", "name"=>"Retained", "active"=>false }, { "id"=>OTHER, "kind"=>"vat", "code"=>"DISABLED", "name"=>"Not selectable", "active"=>false }, { "id"=>BID, "kind"=>"vat", "code"=>"ACTIVE", "name"=>"Active label", "active"=>true } ]
    payload = { tenant_id: TID, book_id: BID, book_name: "SL2030", catalogues_initialized: true, status: "ready", source_version: 2, latest_version: 2, permissions: { configure: true }, pagination: { page: 1, per_page: 50, total_entries: 1, total_pages: 1 }, options: { vat_codes: options, categories: [] }, accounts: [ { id: EID, kind: "posting", number: "0010", name: "Bank", active: true, position: 100, version: 2, vat_entry_id: EID, vat_label: "Retained (inactive)" } ] }
    chart_api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup/accounts"
    stub_request(:get, chart_api).to_return(status: 200, body: payload.to_json)
    get "/tenants/#{TID}/books/#{BID}/chart"
    assert_select "#setup-account_revise-#{EID} select[name=vat_entry_id] option[value='#{EID}'][selected]"
    assert_select "#setup-account_revise-#{EID} select[name=vat_entry_id] option[value='#{OTHER}']", count: 0
    assert_select "#setup-account_create-new select[name=vat_entry_id] option[value='#{EID}']", count: 0
    assert_includes response.body, "Retained (inactive)"
    save = stub_request(:patch, "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup/accounts/#{EID}").with(body: { expected_version: 2, expected_account_version: 2, number: "0010", name: "Bank", kind: "posting", active: true, position: 100, formula: nil, vat_entry_id: EID, category_entry_id: nil }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    key = css_select("#setup-account_revise-#{EID} input[name=form_token]").first["value"]
    patch "/tenants/#{TID}/books/#{BID}/chart", params: { form_token: key, expected_version: "2", expected_account_version: "2", number: "0010", name: "Bank", kind: "posting", active: "true", position: "100", vat_entry_id: EID, category_entry_id: "" }
    assert_requested save
    stub_request(:get, chart_api).to_return(status: 200, body: payload.merge(catalogues_initialized: false).to_json)
    get "/tenants/#{TID}/books/#{BID}/chart"
    assert_select "input[name=form_token]", count: 0
  end
end
