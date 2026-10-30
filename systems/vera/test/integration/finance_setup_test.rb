require "test_helper"

class FinanceSetupTest < ActionDispatch::IntegrationTest
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
  def path = "/tenants/#{TID}/books/#{BID}/setup"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup"
  def data
    { tenant_id: TID, book_id: BID, book_name: "SL2030", status: "ready", source_version: 2, latest_version: 2, permissions: { assign_stewards: true, configure: true }, stewards: [], candidates: [ { identity_id: AID, label: "steward@example.test" } ], occasions: [ { occasion_id: AID, name: "Camp" } ], bindings: [], accounts: [ { id: AID, number: "0010", name: "Bank", kind: "posting", active: true, version: 2, actor_identity_id: AID, application_id: "vera" } ] }
  end
  def view(payload = data)
    stub_request(:get, api).to_return(status: 200, body: payload.to_json)
  end
  def token(action, id = "new")
    css_select("#setup-#{action}-#{id} input[name=form_token]").first["value"]
  end
  def draft(form_token)
    { form_token: form_token, expected_version: "2", expected_account_version: "2", number: "0010", name: "My draft", kind: "posting", active: "true" }
  end

  test "setup forms preserve number strings and use signed scoped command keys" do
    view
    get path
    assert_response :success
    assert_select "input[name=number][value='0010']"
    create = stub_request(:post, "#{api}/accounts").with(body: { expected_version: 2, number: "0020", name: "Cash", kind: "posting" }.to_json, headers: { "Idempotency-Key"=>/\A[0-9a-f-]{36}\z/ }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("account_create"), expected_version: "2", number: "0020", name: "Cash", kind: "posting" }
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
    assert_includes response.body, "Accepted: 0010 · Newer accepted"
    assert_includes response.body, "Reapply draft"
    assert_select "input[name=expected_account_version][value='3']"
    assert_operator response.body.index("My draft"), :<, response.body.index("Accepted: 0010")
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
    assert_redirected_to path
    assert_requested update, times: 1
  end

  test "an explicit retry after an unknown receipt uses the unchanged original body and key" do
    view
    get path
    form_token = token("account_revise", AID)
    original_key = Rails.application.message_verifier(:finance_setup).verified(form_token, purpose: :finance_setup).fetch("key")
    update = stub_request(:patch, "#{api}/accounts/#{AID}").with(headers: { "Idempotency-Key"=>original_key }, body: { expected_version: 2, expected_account_version: 2, number: "0010", name: "My draft", kind: "posting", active: true }).to_timeout
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
    assert_redirected_to path
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
    assert_select "#setup-steward-new"
    assert_select "#setup-account_create-new", count: 0
    assert_select "#setup-binding-new", count: 0
    view(data.merge(status: "pending", latest_version: 3))
    get path
    assert_select "input[name=form_token]", count: 0
    assert_includes response.body, "view is updating"
  end

  test "tampered forms never reach EP" do
    view
    get path
    patch path, params: draft("tampered"), headers: STREAM
    assert_response :unprocessable_entity
    assert_not_requested :patch, "#{api}/accounts/#{AID}"
  end
end
