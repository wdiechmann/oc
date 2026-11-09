require "test_helper"
class ReportsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  PID = "ad763842-2538-4ccb-8445-17e232c37d84"
  RID = "bd763842-2538-4ccb-8445-17e232c37d84"
  REVIEW = "cd763842-2538-4ccb-8445-17e232c37d84"
  LID = "dd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
    stub_request(:get, api).to_return(status: 200, body: data.to_json)
    stub_request(:get, "#{api}/reviews/#{REVIEW}").to_return(status: 200, body: review.to_json)
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/reports"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/reports"
  def account = { id: PID, number: "0010", name: "Bank", active: true, version: 3 }
  def line = { id: LID, code: "BANK", name: "Bank line", kind: "mapping", position: 100, formula: nil, formula_refs: {}, account_ids: [ PID ], sign: 1 }
  def coverage = { unmapped: [], multiple: [], empty_lines: [] }
  def definition = { lines: [ line ], accounts: [ account ], chart_version: 5 }
  def report = { id: RID, name: "Balance", active: true, version: 6, definition: definition, history: [] }
  def data = { tenant_id: TID, book_id: BID, book_name: "Reports", status: "ready", source_version: 5, latest_version: 5, permissions: { configure: true }, reports: [], accounts: [ account ], selected: nil }
  def review = { review_id: REVIEW, expected_version: 5, digest: "abc123", expires_at: 1.hour.from_now.iso8601, accepted_command_id: nil, plan: { report_id: nil, name: "Balance", active: true, definition: definition, before: nil, coverage: coverage } }
  def draft
    { expected_version: "5", name: "Balance", active: "true", report_id: "", expected_report_version: "", lines: { "0"=>line.except(:formula_refs).merge(id: "", account_ids: [ "", PID ], formula: "") } }
  end
  def token = css_select("#accept-report input[name=form_token]").first["value"]
  test "YTD runs the selected saved revision through a read-only scoped API" do
    selected = data.merge(selected: report, coverage: coverage, current_coverage: coverage)
    results = ->(amount) { [ { account_id: LID, status: "ok", amount_minor: amount } ] }
    ytd = { start_date: "2026-01-01", as_of: "2026-11-09", currency: "DKK", journal_count: 2,
      opening: results.call(10000), movement: results.call(-2500), closing: results.call(7500) }
    request = stub_request(:get, api).with(query: { report_id: RID, version: "6", ytd: "1", as_of: "2026-11-09" }).to_return(status: 200, body: selected.merge(ytd: ytd).to_json)
    get path, params: { report_id: RID, version: 6, ytd: 1, as_of: "2026-11-09" }
    assert_response :success
    assert_requested request
    assert_select "table tbody tr", count: 1
    assert_select "td", text: "100,00"
    assert_select "td", text: "-25,00"
    assert_select "td", text: "75,00"
    assert_select "input[name=version][value='6']"
    assert_includes response.body, "2 posted journals"
  end

  test "YTD is discoverable without first opening a definition and explains empty setup" do
    get path
    assert_response :success
    assert_select "section[aria-label='YTD balances']", text: /Create and accept a report definition below first/
    stub_request(:get, api).to_return(status: 200, body: data.merge(reports: [ report ]).to_json)
    get path
    assert_select "section[aria-label='YTD balances']" do
      assert_select "form[method=get]"
      assert_select "select[name=report_id] option[value='#{RID}']", text: "Balance"
      assert_select "input[name=ytd][value='1']"
      assert_select "input[type=submit][value='Run YTD report']"
    end
  end

  test "included YTD runs immediately and customizing saves a book-specific definition" do
    builtin = report.merge(name: "YTD balances", builtin: true)
    stub_request(:get, api).to_return(status: 200, body: data.merge(reports: [ builtin ]).to_json)
    get path
    assert_select "a[href*='ytd=1']", text: "YTD balances"
    stub_request(:get, api).with(query: { report_id: RID }).to_return(status: 200, body: data.merge(reports: [ builtin ], selected: builtin, coverage: coverage, current_coverage: coverage).to_json)
    get path, params: { report_id: RID }
    assert_select "a", text: "Customize YTD definition"
    get path, params: { report_id: RID, edit: "1" }
    assert_select "#report-editor input[name=report_id][value]", count: 0
    assert_select "#report-editor input[name=expected_report_version][value]", count: 0
    assert_select "#report-editor input[name=name][value='YTD balances']"
    assert_select "#report-editor input[name='lines[0][code]'][value=BANK]"
  end

  test "report changes are reviewed before a signed small-pointer acceptance" do
    get path
    assert_response :success
    assert_select "#report-editor"
    attrs = draft.except(:lines).merge(expected_version: 5, active: true, report_id: nil, expected_report_version: nil, lines: [ line.except(:formula_refs).merge(id: nil, formula: "") ])
    command = stub_request(:post, "#{api}/reviews").with(body: attrs).to_return(status: 200, body: review.to_json)
    post "#{path}/review", params: draft
    assert_redirected_to "#{path}?review_id=#{REVIEW}"
    assert_requested command
    follow_redirect!
    assert_includes response.body, "Coverage at review: 0 unmapped"
    stub_request(:post, "#{api}/accept").with(body: { review_id: REVIEW, expected_version: 5, digest: "abc123" }).to_return(status: 200, body: { stream_version: 6 }.to_json)
    patch path, params: { form_token: token, name: "tampered", expected_version: "999" }
    assert_redirected_to path
  end
  test "adding a line and validation errors preserve an unsaved request-local draft" do
    post "#{path}/review", params: draft.merge(intent: "add_line")
    assert_response :success
    assert_select "#report-editor fieldset", count: 2
    assert_select "input[name='lines[0][code]'][value=BANK]"
    stub_request(:post, "#{api}/reviews").to_return(status: 422, body: { error: "invalid_formula" }.to_json)
    post "#{path}/review", params: draft
    assert_response :unprocessable_entity
    assert_includes response.body, "Total formulas reference report line codes"
    assert_select "input[name=name][value=Balance]"
  end
  test "unknown acceptance retains only the original review pointer and key through explicit retry" do
    get path, params: { review_id: REVIEW }
    t = token
    key = Rails.application.message_verifier(:finance_setup).verified(t, purpose: :finance_setup).fetch("key")
    command = stub_request(:post, "#{api}/accept").with(body: { review_id: REVIEW, expected_version: 5, digest: "abc123" }, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: { form_token: t }
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceSetup:report_save", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    assert_select "form[action='#{path}/retry']"
    command.to_return(status: 200, body: { stream_version: 6 }.to_json)
    post "#{path}/retry", params: { expected_version: "99" }
    assert_redirected_to path
    assert_requested command, times: 2
  end
  test "saved revision previews transport exact balances and retain historical account labels" do
    selected = data.merge(reports: [ report ], selected: report, coverage: coverage, current_coverage: coverage)
    stub_request(:get, api).with(query: { report_id: RID, version: "6" }).to_return(status: 200, body: selected.to_json)
    get path, params: { report_id: RID, version: "6" }
    assert_response :success
    assert_includes response.body, "pinned to chart revision 5"
    result = { account_id: LID, status: "ok", amount_minor: -5, exact: { numerator: "-5", denominator: "1" }, inputs: [ account.merge(balance_minor: -5) ], references: [] }
    command = stub_request(:post, "#{api}/#{RID}/preview").with(body: { report_version: 6, balances: { PID=>-5 } }).to_return(status: 200, body: selected.merge(results: [ result ], balances: { PID=>-5 }).to_json)
    post "#{path}/preview", params: { report_id: RID, report_version: "6", balances: { PID=>"-5" } }
    assert_response :success
    assert_includes response.body, "Result: -5 minor units"
    assert_requested command
  end
  test "read-only and lagged views suppress mutation; revoked access clears protected data" do
    stub_request(:get, api).to_return(status: 200, body: data.merge(permissions: { configure: false }).to_json)
    get path
    assert_select "#report-editor", count: 0
    stub_request(:get, api).to_return(status: 200, body: data.merge(status: "pending").to_json)
    get path
    assert_select "#report-editor", count: 0
    stub_request(:get, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    get path
    assert_response :not_found
    assert_not_includes response.body, "Bank"
  end
  test "expired acceptance clears recovery and unavailable selections retain their saved labels" do
    get path, params: { review_id: REVIEW }
    t = token
    stub_request(:post, "#{api}/accept").to_return(status: 410, body: { error: "review_expired" }.to_json)
    patch path, params: { form_token: t }
    assert_response :gone
    assert_select "a[href*='completion']", count: 0
    selected = data.merge(accounts: [], selected: report, reports: [ report ], coverage: coverage, current_coverage: coverage.merge(unavailable: [ PID ]))
    stub_request(:get, api).with(query: { report_id: RID }).to_return(status: 200, body: selected.to_json)
    get path, params: { report_id: RID, edit: "1" }
    assert_select "select[name='lines[0][account_ids][]'] option[value='#{PID}'][selected]", text: /Unavailable.*Bank/
  end
end
