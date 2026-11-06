require "test_helper"

class MonitoringTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TENANT = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  ISSUE = "df763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }

  def sign_in
    stub_request(:get, "#{EP}/me/monitoring-access").to_return(status: 200, body: { platform_monitor: false }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/assignees").to_return(status: 200, body: { assignees: [] }.to_json)
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "private-bearer", expires_at: 1.hour.from_now.iso8601 }.to_json)
    post session_path, params: { token: "one-use-token" }
  end

  def issue
    { id: ISSUE, issue_id: ISSUE, source_version: 2, data: { safe_message: "The application could not complete its response.", code: "application.exception", severity: "error", category: "code", state: "open", count: 3, application: "tom", first_seen: "2026-10-26T10:00:00Z", last_seen: "2026-10-26T10:05:00Z" } }
  end

  test "scopes come from current EP workspaces and scoped lists show safe rows and freshness" do
    sign_in
    stub_request(:get, "#{EP}/me/workspaces").to_return(status: 200, body: { tenants: [ { tenant_id: TENANT, name: "SL" } ], occasions: [] }.to_json)
    get monitoring_path
    assert_response :success
    assert_select "a[href=?]", tenant_monitoring_path(TENANT), text: "SL"
    assert_select "details#monitoring-reporting-status:not([open]) summary", text: "Reporting setup"
    assert_not_includes response.body, "TOM reporting is not enabled"
    assert_select "#monitoring-reporting-status a[href=?]", tenant_monitoring_settings_path(TENANT)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/issues").with(query: { "state" => "open" }).to_return(status: 200, body: { items: [ issue ], next_cursor: nil, freshness: { pending_events: 0, checked_at: "2026-10-26T10:05:00Z" } }.to_json)
    get tenant_monitoring_path(TENANT)
    assert_response :success
    assert_select "a[href=?]", tenant_monitoring_issue_path(TENANT, ISSUE)
    assert_select "[data-monitoring-freshness]", /0 pending/
    assert_not_includes response.body, "private-bearer"
  end

  test "versioned actions stream feedback without redirecting the user" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/issues/#{ISSUE}").to_return(status: 200, body: { status: "ready", issue: issue, expected_version: 2 }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/timeline").with(query: { issue_id: ISSUE }).to_return(status: 200, body: { items: [], next_cursor: nil }.to_json)
    get tenant_monitoring_issue_path(TENANT, ISSUE)
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, "#{EP}/tenants/#{TENANT}/monitoring/issues/#{ISSUE}/actions").with(body: { action: "acknowledge", expected_version: 2 }.to_json).to_return(status: 200, body: { command_id: ISSUE, issue_id: ISSUE, stream_version: 3 }.to_json)
    post tenant_monitoring_issue_action_path(TENANT, ISSUE), params: { action_name: "acknowledge", expected_version: "2", idempotency_key: key }, headers: STREAM
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[target=tom-feedback]"
    assert_not response.redirect?
    assert_not_includes response.body, "private-bearer"
  end

  test "EP outage on a submitted form leaves the form intact and returns an inline stream" do
    stub_request(:post, "#{EP}/auth/magic-links").to_timeout
    post magic_links_path, params: { email: "person@example.test" }, headers: STREAM
    assert_response :service_unavailable
    assert_select "turbo-stream[target=tom-feedback]"
    assert_select "turbo-stream[target=tom-content]", count: 0
    assert_not_includes response.body, "person@example.test"
    assert_not response.redirect?
  end

  test "unexpected TOM failure is reported without raw input and a safe support reference" do
    Rails.application.config.x.monitoring_sources = { "global" => ISSUE }
    stub_request(:post, "#{EP}/auth/magic-links").to_return(status: 202, body: { delivery: [] }.to_json)
    reporter = stub_request(:post, "#{EP}/monitoring/observations").with { |r| p = JSON.parse(r.body); p["code"] == "application.exception" && !r.body.include?("person@example.test") && !r.body.include?("secret-bug") }.to_return(status: 201, body: {}.to_json)
    post magic_links_path, params: { email: "person@example.test" }, headers: STREAM
    assert_response :internal_server_error
    assert_select "turbo-stream[target=tom-feedback]"
    assert_match(/[0-9a-f-]{36}/, response.headers["X-Correlation-ID"])
    assert_not_includes response.body, "secret-bug"
    assert_requested reporter
  ensure
    Rails.application.config.x.monitoring_sources = nil
  end
  test "a TOM failure after EP acceptance can be reconciled without replaying the command" do
    sign_in
    stub_request(:get, "#{EP}/me/workspaces").to_return(status: 200, body: { tenants: [], occasions: [] }.to_json)
    get root_path
    key = css_select("input[name=idempotency_key]").first["value"]
    command = stub_request(:post, "#{EP}/tenants").to_return(status: 201, body: { command_id: ISSUE }.to_json)
    post tenants_path, params: { name: "Private name", idempotency_key: key }, headers: STREAM
    assert_response :internal_server_error
    url = css_select("[data-check-url]").first["data-check-url"]
    assert url.start_with?("/operations/status?")
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "CreateTenant", idempotency_key: key }, headers: { "Authorization" => "Bearer private-bearer" }).to_return(status: 200, body: { status: "accepted", command_id: ISSUE, result: { tenant_id: TENANT } }.to_json)
    get url, headers: STREAM
    assert_response :success
    assert_includes response.body, "EP confirms the action was recorded"
    assert_not_includes response.body, "Private name"
    assert_requested command, times: 1
    delete session_path
    sign_in
    get url, headers: STREAM
    assert_response :not_found
  end

  test "an unknown receipt stays unknown and is never automatically retried" do
    sign_in
    stub_request(:get, "#{EP}/me/workspaces").to_return(status: 200, body: { tenants: [], occasions: [] }.to_json)
    get root_path
    key = css_select("input[name=idempotency_key]").first["value"]
    original = stub_request(:post, "#{EP}/tenants").to_timeout
    post tenants_path, params: { name: "SL", idempotency_key: key }, headers: STREAM
    assert_response :service_unavailable
    url = css_select("[data-check-url]").first["data-check-url"]
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "CreateTenant", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get url, headers: STREAM
    assert_response :accepted
    assert_includes response.body, "Completion is still unknown"
    assert_select "[data-outcome=unknown]"
    assert_requested original, times: 1
  end

  test "monitoring failures do not recursively report and revoked access clears its old view" do
    sign_in
    Rails.application.config.x.monitoring_sources = { "global" => ISSUE }
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/issues").with(query: { state: "open" }).to_return(status: 503, body: { error: "view_stopped" }.to_json)
    get tenant_monitoring_path(TENANT), headers: STREAM
    assert_response :service_unavailable
    assert_select "turbo-stream[target=monitoring-list]"
    assert_not_requested :post, "#{EP}/monitoring/observations"
  ensure
    Rails.application.config.x.monitoring_sources = nil
  end

  test "foreign URL denials use the global reporting scope and never the named tenant" do
    sign_in
    global = "d65e8bf0-7695-41dc-bf08-5a94faee1570"
    Rails.application.config.x.monitoring_sources = { "global" => global, "tenant:#{TENANT}" => ISSUE }
    report = stub_request(:post, "#{EP}/monitoring/observations").with { |r| JSON.parse(r.body)["source_id"] == global }.to_return(status: 201, body: {}.to_json)
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 404, body: { error: "not_found" }.to_json)
    get tenant_path(TENANT)
    assert_response :not_found
    assert_requested report, times: 1
  ensure
    Rails.application.config.x.monitoring_sources = nil
  end

  test "delivery attempts are reported but local test mail is not claimed as provider acceptance" do
    Rails.application.config.x.monitoring_sources = { "global" => ISSUE }
    stub_request(:post, "#{EP}/auth/magic-links").to_return(status: 202, body: { delivery: { email: "private@example.test", token: "a" * 43, expires_at: 10.minutes.from_now.iso8601 } }.to_json)
    reported = stub_request(:post, "#{EP}/monitoring/delivery-outcomes").with { |r| p = JSON.parse(r.body); p["code"] == "delivery.attempted" && p["related"]["delivery_attempt_id"].match?(Monitoring::Reporter::UUID) && !r.body.include?("private@example.test") && !r.body.include?("a" * 43) }.to_return(status: 201, body: {}.to_json)
    post magic_links_path, params: { email: "private@example.test" }
    assert_redirected_to new_session_path
    assert_requested reported, times: 1
    assert_equal 1, Mail::TestMailer.deliveries.length
  ensure
    Rails.application.config.x.monitoring_sources = nil
  end

  test "server renders local Turbo assets with no inline scripts and stream validation preserves safe input" do
    get new_session_path
    assert_select "script[src*='turbo'][type=module]"
    assert_select "script:not([src])", count: 0
    assert_select "#tom-feedback[aria-live=polite]"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    nonce = css_select("meta[name=csp-nonce]").first["content"]
    assert_includes response.headers["Content-Security-Policy"], "'nonce-#{nonce}'"
    stub_request(:post, "#{EP}/auth/magic-links").to_return(status: 422, body: { error: "invalid_email" }.to_json)
    post magic_links_path, params: { email: "invalid" }, headers: STREAM
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target=tom-feedback]"
    assert_select "turbo-stream[target=tom-content]", count: 0
  end

  test "observation transport failure stays bounded and does not replace the original error" do
    Rails.application.config.x.monitoring_sources = { "global" => ISSUE }
    stub_request(:post, "#{EP}/auth/magic-links").to_return(status: 202, body: { delivery: [] }.to_json)
    report = stub_request(:post, "#{EP}/monitoring/observations").to_timeout
    post magic_links_path, params: { email: "private@example.test" }, headers: STREAM
    assert_response :internal_server_error
    assert_requested report, times: 1
    assert_select "turbo-stream[target=tom-feedback]"
  ensure
    Rails.application.config.x.monitoring_sources = nil
  end
  test "monitoring filter submissions do not warn about route and form parameters" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}/monitoring/issues").with(query: { severity: "error" }).to_return(status: 200, body: { items: [], freshness: {} }.to_json)
    notices = []
    subscriber = ->(*args) { notices << args.last[:keys] }
    ActiveSupport::Notifications.subscribed(subscriber, "unpermitted_parameters.action_controller") do
      get tenant_monitoring_path(TENANT), params: { view: "issues", severity: "error", state: "", commit: "Apply filters" }, headers: STREAM
    end
    assert_response :success
    assert_empty notices
  end
end
