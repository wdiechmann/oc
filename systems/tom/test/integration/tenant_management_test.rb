require "test_helper"

class TenantManagementTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TENANT = "657df2d1-0f99-4007-a914-e26de1d58dc9"

  def sign_in
    stub_request(:post, "#{EP}/auth/magic-links/verify").with(body: { token: "one-use-token" }.to_json)
      .to_return(status: 200, body: { token: "private-bearer", expires_at: 1.hour.from_now.iso8601 }.to_json)
    post session_path, params: { token: "one-use-token" }
    assert_redirected_to root_path
  end

  test "database-free app shows sign in and protects tenant pages" do
    assert_not defined?(ActiveRecord::Base)
    get new_session_path
    assert_response :success
    assert_select "h1", "Your camp starts here."
    get tenant_path(TENANT)
    assert_redirected_to new_session_path
  end

  test "requests a magic link without revealing it" do
    stub_request(:post, "#{EP}/auth/magic-links").with(body: { email: "person@example.test" }.to_json)
      .to_return(status: 202, body: { status: "check_your_email" }.to_json)
    post magic_links_path, params: { email: "person@example.test" }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=status]", /Check your email/
  end

  test "creates tenant through EP and reads projection without exposing bearer" do
    sign_in
    get root_path
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, "#{EP}/tenants").with(headers: { "Authorization" => "Bearer private-bearer", "Idempotency-Key" => /.+/ }, body: { name: "Spejdernes Lejr" }.to_json)
      .to_return(status: 201, body: { tenant_id: TENANT }.to_json)
    post tenants_path, params: { name: "Spejdernes Lejr", idempotency_key: key }
    assert_redirected_to tenant_path(TENANT)
    stub_request(:get, "#{EP}/tenants/#{TENANT}").with(headers: { "Authorization" => "Bearer private-bearer" })
      .to_return(status: 200, body: { name: "Spejdernes Lejr", status: "ready", source_version: 2, tenant_id: TENANT }.to_json)
    follow_redirect!
    assert_response :success
    assert_select "h1", "Spejdernes Lejr"
    assert_select "[data-source-version]", "2"
    assert_not_includes response.body, "private-bearer"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "pending projection can be refreshed" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 202, body: { status: "pending", tenant_id: TENANT }.to_json)
    get tenant_path(TENANT)
    assert_response :success
    assert_select "h1", "Preparing your tenant"
    assert_select "a", "Refresh status"
  end

  test "EP access denials are not overridden by the UI" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 404, body: { error: "not_found" }.to_json)
    get tenant_path(TENANT)
    assert_response :not_found
    assert_select "h1", "Tenant unavailable"
  end

  test "expired backend session returns to sign in" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 401, body: { error: "unauthenticated" }.to_json)
    get tenant_path(TENANT)
    assert_redirected_to new_session_path
  end

  test "backend outage returns a usable error" do
    stub_request(:post, "#{EP}/auth/magic-links").to_timeout
    post magic_links_path, params: { email: "person@example.test" }
    assert_response :service_unavailable
    assert_select "[role=alert]", /temporarily unavailable/
  end

  test "sign out clears the browser session" do
    sign_in
    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end
  test "uncertain create outcome retains the same idempotency key for retry" do
    sign_in
    get root_path
    key = css_select("input[name=idempotency_key]").first["value"]
    failed = stub_request(:post, "#{EP}/tenants").to_timeout
    post tenants_path, params: { name: "Camp", idempotency_key: key }
    assert_response :service_unavailable
    get root_path
    assert_equal key, css_select("input[name=idempotency_key]").first["value"]
    remove_request_stub(failed)
    stub_request(:post, "#{EP}/tenants").with(headers: { "Idempotency-Key" => key })
      .to_return(status: 200, body: { tenant_id: TENANT, replayed: true }.to_json)
    post tenants_path, params: { name: "Camp", idempotency_key: key }
    assert_redirected_to tenant_path(TENANT)
  end

  test "forged command keys never reach EP" do
    sign_in
    post tenants_path, params: { name: "Camp", idempotency_key: "forged" }
    assert_redirected_to root_path
    assert_not_requested :post, "#{EP}/tenants"
  end

  test "stopped projections are not served from browser state" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 503, body: { error: "view_stopped" }.to_json)
    get tenant_path(TENANT)
    assert_response :service_unavailable
    assert_select "[role=alert]", /temporarily unavailable/
  end

  test "HTML forms enforce CSRF protection" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post magic_links_path, params: { email: "person@example.test" }
    assert_response :unprocessable_entity
    assert_not_requested :post, "#{EP}/auth/magic-links"
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
