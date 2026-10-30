require "test_helper"
class PeriodsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  PID = "bd763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept"=>"text/vnd.turbo-stream.html" }
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "period-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/periods"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/periods"
  def data(status = "draft")
    { tenant_id: TID, book_id: BID, book_name: "SL2030", timezone: "Europe/Copenhagen", accounting_authority: "ep", status: "ready", source_version: 2, latest_version: 2, permissions: { configure: true, reopen: true }, periods: [ { id: PID, name: "January", start_date: "2030-01-01", end_date: "2030-01-31", status: status, version: 2, history: [ { event_type: "PeriodCreated", name: "January", start_date: "2030-01-01", end_date: "2030-01-31", status: "draft", version: 1, actor_identity_id: PID, application_id: "vera", accepted_at: "2026-10-30T13:00:00Z" } ] } ] }
  end
  def view(payload = data)
    stub_request(:get, api).to_return(status: 200, body: payload.to_json)
  end
  def token(action, id = PID) = css_select("##{action}-#{id} input[name=form_token]").first["value"]

  test "separate period view shows inclusive book dates, history and signed create commands" do
    view
    get path
    assert_response :success
    assert_includes response.body, "Europe/Copenhagen"
    assert_includes response.body, "Period history"
    create = stub_request(:post, api).with(body: { expected_version: 2, name: "February", start_date: "2030-02-01", end_date: "2030-02-28" }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token("period_create", "new"), expected_version: "2", name: "February", start_date: "2030-02-01", end_date: "2030-02-28" }
    assert_redirected_to path
    assert_requested create
  end

  test "overlap and stale corrections preserve the submitted draft above accepted metadata" do
    view
    get path
    key = token("period_revise")
    revised = data
    revised[:periods][0].merge!(name: "Newer January", version: 3)
    revised.merge!(source_version: 3, latest_version: 3)
    view(revised)
    save = stub_request(:patch, "#{api}/#{PID}").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2", name: "My January", start_date: "2030-01-02", end_date: "2030-01-31" }, headers: STREAM
    assert_response :conflict
    assert_select "turbo-stream[target=vera-book-content]"
    assert_select "input[name=name][value='My January']"
    assert_select "input[name=start_date][value='2030-01-02']"
    assert_select "input[name=expected_period_version][value='3']"
    assert_operator response.body.index("My January"), :<, response.body.index("Newer January")
    assert_requested save, times: 1
  end

  test "closed periods require explicit reopening permission and a retained reason" do
    view(data("closed").merge(permissions: { configure: true, reopen: false }))
    get path
    assert_select "form[id^=period_reopen]", count: 0
    view(data("closed"))
    get path
    assert_select "textarea[name=reason][required][maxlength='500']"
    key = token("period_reopen")
    reopen = stub_request(:post, "#{api}/#{PID}/reopen").with(body: { expected_version: 2, expected_period_version: 2, reason: "Keep my reason" }).to_return(status: 422, body: { error: "invalid_reason" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2", reason: "Keep my reason" }, headers: STREAM
    assert_response :unprocessable_entity
    assert_select "textarea[name=reason]", text: "Keep my reason"
    assert_requested reopen, times: 1
  end

  test "lost close responses reconcile with the original private receipt and never repeat the close" do
    view(data("open"))
    get path
    key = token("period_close")
    command_key = Rails.application.message_verifier(:finance_setup).verified(key, purpose: :finance_setup).fetch("key")
    close = stub_request(:post, "#{api}/#{PID}/close").to_timeout
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2" }, headers: STREAM
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']", text: "Check completion"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinancePeriod:close", idempotency_key: command_key }).to_return(status: 200, body: { status: "accepted", result: { period_id: PID } }.to_json)
    get "#{path}/completion"
    assert_redirected_to path
    assert_requested close, times: 1
  end

  test "pending projections, readonly authority and revoked access cannot mutate periods" do
    view(data.merge(status: "pending", latest_version: 3))
    get path
    assert_select "input[name=form_token]", count: 0
    view(data.merge(permissions: { configure: false, reopen: false }))
    get path
    assert_select "input[name=form_token]", count: 0
    view
    get path
    key = token("period_open")
    stub_request(:post, "#{api}/#{PID}/open").to_return(status: 404, body: { error: "not_found" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2" }, headers: STREAM
    assert_response :not_found
    assert_select "turbo-stream[target=vera-book-content]"
    assert_not_includes response.body, "January"
  end

  test "a date draft stays visible if another steward opens the period before the correction" do
    view
    get path
    key = token("period_revise")
    view(data("open").merge(source_version: 3, latest_version: 3))
    stub_request(:patch, "#{api}/#{PID}").to_return(status: 409, body: { error: "invalid_transition" }.to_json)
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2", name: "Keep my correction", start_date: "2030-01-02", end_date: "2030-01-31" }, headers: STREAM
    assert_response :conflict
    assert_includes response.body, "Keep my correction"
    assert_includes response.body, "2030-01-02"
    assert_select "form[id^=period_revise]", count: 0
    assert_select "turbo-stream[action=update][target=vera-feedback]"
  end

  test "an explicit period retry after checking uses only the original command body and key" do
    view(data("open"))
    get path
    key = token("period_close")
    command_key = Rails.application.message_verifier(:finance_setup).verified(key, purpose: :finance_setup).fetch("key")
    close = stub_request(:post, "#{api}/#{PID}/close").with(headers: { "Idempotency-Key"=>command_key }, body: { expected_version: 2, expected_period_version: 2 }).to_timeout
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2" }, headers: STREAM
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinancePeriod:close", idempotency_key: command_key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion", headers: STREAM
    assert_select "input[value='Retry original request']"
    assert_requested close, times: 1
    close.to_return(status: 200, body: { stream_version: 3 }.to_json)
    post "#{path}/retry", params: { expected_version: "999" }
    assert_redirected_to path
    assert_requested close, times: 2
  end

  test "access loss during an uncertain retry preserves private receipt reconciliation" do
    view(data("open"))
    get path
    key = token("period_close")
    command_key = Rails.application.message_verifier(:finance_setup).verified(key, purpose: :finance_setup).fetch("key")
    close = stub_request(:post, "#{api}/#{PID}/close").to_timeout
    patch path, params: { form_token: key, expected_version: "2", expected_period_version: "2" }, headers: STREAM
    receipt = stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinancePeriod:close", idempotency_key: command_key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion", headers: STREAM
    close.to_return(status: 404, body: { error: "not_found" }.to_json)
    post "#{path}/retry", headers: STREAM
    assert_response :not_found
    assert_select "turbo-stream[target=vera-book-content]"
    assert_select "a[href='#{path}/completion']", text: "Check completion"
    assert_not_includes response.body, "January"
    receipt.to_return(status: 200, body: { status: "accepted", result: { period_id: PID } }.to_json)
    get "#{path}/completion"
    assert_redirected_to path
    assert_requested close, times: 2
  end

  test "tenant administrators explicitly assign the separate reopening permission" do
    root = "#{EP}/tenants/#{TID}/finance/books/#{BID}/setup"
    setup_data = { tenant_id: TID, book_id: BID, book_name: "SL2030", status: "ready", source_version: 1, latest_version: 1, permissions: { assign_stewards: true, configure: true }, stewards: [ { identity_id: PID, can_reopen_periods: false } ], candidates: [ { identity_id: PID, label: "owner@example.test" } ], occasions: [], bindings: [], accounts: [] }
    stub_request(:get, root).to_return(status: 200, body: setup_data.to_json)
    get "/tenants/#{TID}/books/#{BID}/setup"
    key = css_select("#setup-reopening_authority-new input[name=form_token]").first["value"]
    grant = stub_request(:post, "#{root}/reopening-authority").with(body: { expected_version: 1, identity_id: PID, allow: true }).to_return(status: 200, body: { stream_version: 2 }.to_json)
    patch "/tenants/#{TID}/books/#{BID}/setup", params: { form_token: key, expected_version: "1", identity_id: PID, allow: "true" }
    assert_response :see_other
    assert_requested grant
  end
end
