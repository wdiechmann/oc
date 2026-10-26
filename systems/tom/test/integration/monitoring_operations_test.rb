require "test_helper"
require "tmpdir"
require Rails.root.join("..", "monitor", "lib", "ep_monitor", "spool").to_s
class MonitoringOperationsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  SID = "df763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept"=>"text/vnd.turbo-stream.html" }
  setup do
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "private-bearer", expires_at: 1.hour.from_now.iso8601 }.to_json)
    post session_path, params: { token: "one-use-token" }
  end
  teardown do
    Rails.application.config.x.monitoring_spool = nil
    Rails.application.config.x.monitoring_sources = nil
    File.unlink(Monitoring::Dispatcher.heartbeat_path) if File.file?(Monitoring::Dispatcher.heartbeat_path)
  end

  def settings_stubs
    stub_request(:get, "#{EP}/tenants/#{TID}/monitoring/sources").to_return(status: 200, body: { sources: [ { source_id: SID, backend_id: "test-backend", status: "active" } ], backends: [ "test-backend" ] }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TID}/monitoring/rules").to_return(status: 200, body: { rules: [] }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TID}/monitoring/assignees").to_return(status: 200, body: { assignees: [ { identity_id: SID, label: "operator@example.test" } ] }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TID}/monitoring/alerts").to_return(status: 200, body: { alerts: [] }.to_json)
    stub_request(:get, "#{EP}/monitoring/catalogue").to_return(status: 200, body: { codes: { "application.exception"=>{ severity: "error" } } }.to_json)
  end
  test "source administration and rule form use approved scopes and named recipients" do
    settings_stubs
    get tenant_monitoring_settings_path(TID)
    assert_response :success
    assert_select "h1", "Reporting sources and alerts"
    assert_select "label", text: "operator@example.test"
    assert_not_includes response.body, "private-bearer"
    key = css_select("input[name=idempotency_key]").first["value"]
    created = stub_request(:post, "#{EP}/tenants/#{TID}/monitoring/sources").with(body: { backend_id: "test-backend" }.to_json).to_return(status: 200, body: { source_id: SID }.to_json)
    post tenant_monitoring_settings_path(TID), params: { configuration_action: "register", backend_id: "test-backend", idempotency_key: key }, headers: STREAM
    assert_response :success
    assert_select "turbo-stream[target=tom-feedback]"
    assert_requested created, times: 1
  end

  test "failed reporting remains encrypted and can be replayed with its original ID" do
    Dir.mktmpdir("tom-spool-test") do |dir|
      spool = EpMonitor::Spool.new(directory: dir, key: Base64.strict_encode64("x"*32))
      Rails.application.config.x.monitoring_spool = spool
      Rails.application.config.x.monitoring_sources = { "global"=>SID }
      stub_request(:post, "#{EP}/auth/magic-links").to_return(status: 202, body: { delivery: [] }.to_json)
      report = stub_request(:post, "#{EP}/monitoring/observations").to_timeout
      post magic_links_path, params: { email: "private@example.test" }, headers: STREAM
      assert_response :internal_server_error
      assert_equal 1, spool.statistics[:pending]
      body = spool.claim.fetch(:body).fetch("observation")
      assert_equal "application.exception", body["code"]
      assert body["diagnostic"]
      refute JSON.generate(body).include?("private@example.test")
      assert_requested report, times: 1
    end
  end

  test "alert delivery acknowledges a test sink without claiming inbox delivery or reporting loops" do
    material = { alert_id: SID, attempt_id: TID, issue_id: SID, tenant_id: TID, code: "application.exception", safe_message: "The application could not complete its response.", recipients: [ "operator@example.test" ] }
    stub_request(:post, "#{EP}/monitoring/alerts/claim").to_return(status: 200, body: { alerts: [ material ] }.to_json)
    acknowledged = stub_request(:post, "#{EP}/monitoring/alerts/#{SID}/outcome").with(body: { attempt_id: TID, status: "test_accepted" }.to_json).to_return(status: 200, body: { status: "test_accepted" }.to_json)
    assert_equal 1, Monitoring::Dispatcher.tick
    assert_equal [ "operator@example.test" ], Mail::TestMailer.deliveries.last.to
    assert_requested acknowledged, times: 1
    assert_not_requested :post, "#{EP}/monitoring/observations"
    assert_not_requested :post, "#{EP}/monitoring/delivery-outcomes"
    get "/up/monitoring"
    assert_response :success
  end

  test "ordinary tenant administration cannot disclose global diagnostics" do
    denied = stub_request(:get, "#{EP}/monitoring/platform/issues").with(query: { state: "open" }).to_return(status: 404, body: { error: "not_found" }.to_json)
    get platform_monitoring_path
    assert_response :not_found
    assert_requested denied
    stub_request(:get, "#{EP}/tenants/#{TID}/monitoring/observations/#{SID}/diagnostic").to_return(status: 404, body: { error: "not_found" }.to_json)
    get tenant_monitoring_diagnostic_path(TID, SID)
    assert_response :not_found
  end
  test "maintenance suppression forwards the chosen UTC deadline and current version" do
    settings_stubs
    get tenant_monitoring_settings_path(TID)
    key = css_select("input[name=idempotency_key]").first["value"]
    deadline = 1.hour.from_now.utc.change(sec: 0)
    sent = stub_request(:post, "#{EP}/tenants/#{TID}/monitoring/rules/#{SID}/suppression")
      .with(body: { expected_version: 3, reason: "maintenance", until: deadline.iso8601 }.to_json)
      .to_return(status: 200, body: { version: 4 }.to_json)
    post tenant_monitoring_settings_path(TID), params: { configuration_action: "suppression", record_id: SID, expected_version: "3", until: deadline.strftime("%Y-%m-%dT%H:%M"), idempotency_key: key }, headers: STREAM
    assert_response :success
    assert_requested sent, times: 1
  end
end
