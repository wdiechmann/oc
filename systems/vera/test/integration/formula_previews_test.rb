require "test_helper"

class FormulaPreviewsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  PID = "ad763842-2538-4ccb-8445-17e232c37d84"
  CID = "bd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
    stub_request(:get, api).to_return(status: 200, body: data.to_json)
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/formula_preview"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/formula-preview"
  def data
    { tenant_id: TID, book_id: BID, book_name: "Formula fixture", source_version: 5, balances: {}, results: nil, rows: [
      { id: PID, number: "0099", name: "Bank", kind: "posting", active: false },
      { id: CID, number: nil, name: "Total", kind: "calculation", active: true, formula: "[0010] / 2", formula_refs: { "0010"=>PID } }
    ] }
  end
  test "preview follows saved references, keeps blank balances unknown and transports integers exactly" do
    get path
    assert_response :success
    assert_includes response.body, "[0010] → 0099"
    assert_select "input[name='balances[#{PID}]']"
    assert_select "input[name=form_token]", count: 0
    result = { account_id: CID, status: "ok", amount_minor: -1, exact: { numerator: "-1", denominator: "2" }, references: [ { reference: "0010", account_id: PID, number: "0099", name: "Bank", active: false, amount_minor: -1, exact: { numerator: "-1", denominator: "2" } } ], inputs: [ { number: "0099", name: "Bank", active: false, balance_minor: -1 } ] }
    command = stub_request(:post, api).with(body: { expected_version: 5, balances: { PID=>-1 } }).to_return(status: 200, body: data.merge(balances: { PID=>-1 }, results: [ result ]).to_json)
    post path, params: { expected_version: "5", balances: { PID=>"-1" } }
    assert_response :success
    assert_includes response.body, "Result: -1 minor units"
    assert_includes response.body, "Exact: -1/2"
    assert_requested command
    stub_request(:post, api).with(body: { expected_version: 5, balances: {} }).to_return(status: 200, body: data.merge(results: [ { account_id: CID, status: "error", error: "missing_balance", related_account_id: PID } ]).to_json)
    post path, params: { expected_version: "5", balances: { PID=>"" } }
    assert_includes response.body, "Enter a test balance"
  end
  test "stale revisions preserve entered balances and show the current chart without stale totals" do
    stub_request(:post, api).to_return(status: 409, body: { error: "version_conflict" }.to_json)
    post path, params: { expected_version: "4", balances: { PID=>"35" } }
    assert_response :conflict
    assert_select "input[name='balances[#{PID}]'][value='35']"
    assert_includes response.body, "chart changed"
    assert_not_includes response.body, "Result:"
  end
  test "revoked access clears protected data and preview failures do not start command recovery" do
    stub_request(:post, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    post path, params: { expected_version: "5", balances: { PID=>"10" } }
    assert_response :not_found
    assert_not_includes response.body, "Bank"
    assert_not_includes response.body, "value=\"10\""
    stub_request(:post, api).to_timeout
    post path, params: { expected_version: "5", balances: { PID=>"10" } }
    assert_response :service_unavailable
    assert_includes response.body, "retry this calculation"
    assert_select "a[href*='completion']", count: 0
  end
  test "malformed amounts remain visible as errors and no calculations occur on GET" do
    stub_request(:post, api).with(body: { expected_version: 5, balances: { PID=>nil } }).to_return(status: 422, body: { error: "invalid_balances" }.to_json)
    post path, params: { expected_version: "5", balances: { PID=>"1.25" } }
    assert_response :unprocessable_entity
    assert_select "input[name='balances[#{PID}]'][value='1.25']"
    get path
    assert_response :success
    assert_select "input[name='balances[#{PID}]'][value]", count: 0
  end
end
