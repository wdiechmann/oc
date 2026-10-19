require "test_helper"

class TenantManagementTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TENANT = "657df2d1-0f99-4007-a914-e26de1d58dc9"

  def sign_in
    stub_request(:get, "#{EP}/me/occasion-admin-invitations").to_return(status: 200, body: { invitations: [] }.to_json)
    stub_request(:get, %r{#{EP}/tenants/[^/]+/occasions$}).to_return(status: 200, body: { status: "ready", occasions: [] }.to_json)
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
  test "same-origin forms submit with CSRF protection and preserve browser origin" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get new_session_path
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    token = css_select("form[action='/magic_links'] input[name=authenticity_token]").first["value"]
    stub_request(:post, "#{EP}/auth/magic-links")
      .to_return(status: 202, body: { status: "check_your_email" }.to_json)
    post magic_links_path, params: { email: "person@example.test", authenticity_token: token }, headers: { "Origin" => "http://www.example.com" }
    assert_redirected_to new_session_path
    post magic_links_path, params: { email: "person@example.test", authenticity_token: token }, headers: { "Origin" => "http://foreign.example" }
    assert_response :unprocessable_entity
    assert_requested :post, "#{EP}/auth/magic-links", times: 1
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
  test "create occasion form posts only intended fields and shows projected result" do
    sign_in
    get new_tenant_occasion_path(TENANT)
    assert_response :success
    assert_select "h1", "Create an occasion"
    key = css_select("input[name=idempotency_key]").first["value"]
    oid = "b4f78441-4b07-49cd-b42f-744fc086decb"
    stub_request(:post, "#{EP}/tenants/#{TENANT}/occasions")
      .with(headers: { "Authorization" => "Bearer private-bearer", "Idempotency-Key" => key }, body: { name: "SL2030", slug: "sl2030", expires_at: "2031-01-01T23:59:59.000000Z", assign_self_as_admin: true }.to_json)
      .to_return(status: 201, body: { occasion_id: oid }.to_json)
    post tenant_occasions_path(TENANT), params: { name: "SL2030", slug: "sl2030", expires_on: "2031-01-01", assign_self_as_admin: "1", idempotency_key: key, status: "active", tenant_id: TENANT }
    assert_redirected_to tenant_occasion_path(TENANT, oid)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/occasions/#{oid}")
      .to_return(status: 200, body: { name: "SL2030", slug: "sl2030", lifecycle: "draft", recruitment_state: "closed", status: "ready", expires_at: "2031-01-01T23:59:59Z", source_version: 2 }.to_json)
    follow_redirect!
    assert_response :success
    assert_select "h1", "SL2030"
    assert_select "dd", "Closed"
  end

  test "occasion forms reject forged keys and invalid dates without backend mutations" do
    sign_in
    get new_tenant_occasion_path(TENANT)
    key = css_select("input[name=idempotency_key]").first["value"]
    post tenant_occasions_path(TENANT), params: { name: "SL", slug: "sl", expires_on: "invalid", idempotency_key: key }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /date/
    post tenant_occasions_path(TENANT), params: { name: "SL", slug: "sl", expires_on: "2031-01-01", idempotency_key: "forged" }
    assert_redirected_to new_tenant_occasion_path(TENANT)
    assert_not_requested :post, "#{EP}/tenants/#{TENANT}/occasions"
  end

  test "tenant overview lists occasions returned by EP" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}").to_return(status: 200, body: { name: "SL", status: "ready", tenant_id: TENANT, source_version: 2 }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/occasions").to_return(status: 200, body: { status: "ready", occasions: [ { name: "SL2030", slug: "sl2030", occasion_id: TENANT, lifecycle: "draft" } ] }.to_json)
    get tenant_path(TENANT)
    assert_select "a[href=?]", tenant_occasion_path(TENANT, TENANT), text: "SL2030"
    assert_select "a[href=?]", new_tenant_occasion_path(TENANT), text: "Create occasion"
  end

  test "duplicate occasion short names retain form fields and command key" do
    sign_in
    get new_tenant_occasion_path(TENANT)
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, "#{EP}/tenants/#{TENANT}/occasions").to_return(status: 409, body: { error: "slug_taken" }.to_json)
    post tenant_occasions_path(TENANT), params: { name: "SL2030", slug: "sl2030", expires_on: "2031-01-01", idempotency_key: key }
    assert_response :conflict
    assert_select "[role=alert]", /already used/
    assert_select "input[name=slug][value=sl2030]"
    assert_select "input[name=idempotency_key][value=?]", key
  end
  test "tenant admin creates and revokes an invitation through EP" do
    sign_in
    iid = "df763842-2538-4ccb-8445-17e232c37d84"
    list = stub_request(:get, "#{EP}/tenants/#{TENANT}/admin-invitations").to_return(status: 200, body: { invitations: [] }.to_json)
    get tenant_admin_invitations_path(TENANT)
    assert_response :success
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, "#{EP}/tenants/#{TENANT}/admin-invitations")
      .with(body: { email: "prospect@example.test" }.to_json, headers: { "Authorization" => "Bearer private-bearer", "Idempotency-Key" => key })
      .to_return(status: 201, body: { invitation_id: iid }.to_json)
    post tenant_admin_invitations_path(TENANT), params: { email: "prospect@example.test", idempotency_key: key }
    assert_redirected_to tenant_admin_invitations_path(TENANT)
    remove_request_stub(list)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/admin-invitations").to_return(status: 200, body: { invitations: [ { invitation_id: iid, email: "prospect@example.test", status: "pending", expires_at: "2031-01-01T00:00:00Z" } ] }.to_json)
    follow_redirect!
    assert_select "td", "prospect@example.test"
    assert_select "input[value=Revoke]"
    stub_request(:post, "#{EP}/tenants/#{TENANT}/admin-invitations/#{iid}/revoke").to_return(status: 200, body: { status: "revoked" }.to_json)
    post revoke_tenant_admin_invitation_path(TENANT, iid)
    assert_redirected_to tenant_admin_invitations_path(TENANT)
  end

  test "recipient sees inbox and explicitly accepts under their EP identity" do
    sign_in
    iid = "df763842-2538-4ccb-8445-17e232c37d84"
    stub_request(:get, "#{EP}/me/tenant-admin-invitations").with(headers: { "Authorization" => "Bearer private-bearer" })
      .to_return(status: 200, body: { invitations: [ { invitation_id: iid, tenant_id: TENANT, tenant_name: "SL", expires_at: "2031-01-01T00:00:00Z" } ] }.to_json)
    get invitations_path
    assert_select "h1", "Your invitations"
    assert_select "input[value='Accept tenant-admin invitation']"
    stub_request(:post, "#{EP}/tenants/#{TENANT}/admin-invitations/#{iid}/accept")
      .with(headers: { "Idempotency-Key" => "accept-invitation:#{iid}" })
      .to_return(status: 200, body: { tenant_id: TENANT, status: "accepted" }.to_json)
    post accept_tenant_admin_invitation_path(TENANT, iid)
    assert_redirected_to tenant_path(TENANT)
  end

  test "forged invitation creation key never reaches EP" do
    sign_in
    post tenant_admin_invitations_path(TENANT), params: { email: "prospect@example.test", idempotency_key: "forged" }
    assert_redirected_to tenant_admin_invitations_path(TENANT)
    assert_not_requested :post, "#{EP}/tenants/#{TENANT}/admin-invitations"
  end
  test "occasion admin invitation form uses occasion-scoped EP commands" do
    sign_in
    oid = "b4f78441-4b07-49cd-b42f-744fc086decb"
    iid = "df763842-2538-4ccb-8445-17e232c37d84"
    url = "#{EP}/tenants/#{TENANT}/occasions/#{oid}/admin-invitations"
    stub_request(:get, url).to_return(status: 200, body: { invitations: [], occasion_name: "SL2030" }.to_json)
    get tenant_occasion_admin_invitations_path(TENANT, oid)
    assert_response :success
    assert_select "h1", "Share occasion administration"
    assert_select "p", "Occasion: SL2030"
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, url).with(body: { email: "prospect@example.test" }.to_json, headers: { "Idempotency-Key" => key }).to_return(status: 201, body: { invitation_id: iid, occasion_id: oid }.to_json)
    post tenant_occasion_admin_invitations_path(TENANT, oid), params: { email: "prospect@example.test", idempotency_key: key }
    assert_redirected_to tenant_occasion_admin_invitations_path(TENANT, oid)
    stub_request(:post, "#{url}/#{iid}/revoke").to_return(status: 200, body: { status: "revoked" }.to_json)
    post revoke_tenant_occasion_admin_invitation_path(TENANT, oid, iid)
    assert_redirected_to tenant_occasion_admin_invitations_path(TENANT, oid)
    assert_not_requested :post, "#{EP}/tenants/#{TENANT}/admin-invitations"
  end

  test "occasion recipient inbox clearly scopes acceptance and preserves access after accepting" do
    sign_in
    oid = "b4f78441-4b07-49cd-b42f-744fc086decb"
    iid = "df763842-2538-4ccb-8445-17e232c37d84"
    invitation = { invitation_id: iid, tenant_id: TENANT, occasion_id: oid, tenant_name: "SL", occasion_name: "SL2030", role: "occasion_admin", status: "pending", expires_at: "2031-01-01T00:00:00Z" }
    stub_request(:get, "#{EP}/me/tenant-admin-invitations").to_return(status: 200, body: { invitations: [] }.to_json)
    stub_request(:get, "#{EP}/me/occasion-admin-invitations").to_return(status: 200, body: { invitations: [ invitation ] }.to_json)
    get invitations_path
    assert_select "h2", "SL2030"
    assert_select "input[value='Accept occasion-admin invitation']"
    stub_request(:post, "#{EP}/tenants/#{TENANT}/occasions/#{oid}/admin-invitations/#{iid}/accept").to_return(status: 200, body: { tenant_id: TENANT, occasion_id: oid, status: "accepted" }.to_json)
    post accept_tenant_occasion_admin_invitation_path(TENANT, oid, iid)
    assert_redirected_to tenant_occasion_path(TENANT, oid)
    stub_request(:get, "#{EP}/tenants/#{TENANT}/occasions/#{oid}").to_return(status: 200, body: { name: "SL2030", status: "ready", can_manage_admins: false }.to_json)
    follow_redirect!
    assert_select "h1", "SL2030"
    assert_select "a[href=?]", tenant_occasion_admin_invitations_path(TENANT, oid), count: 0
    stub_request(:get, "#{EP}/me/occasion-admin-invitations").to_return(status: 200, body: { invitations: [ invitation.merge(status: "accepted") ] }.to_json)
    get invitations_path
    assert_select "a[href=?]", tenant_occasion_path(TENANT, oid), text: "Open occasion"
    assert_select "input[value='Accept occasion-admin invitation']", count: 0
  end

  test "occasion invitation creation key cannot cross to another scope" do
    sign_in
    stub_request(:get, "#{EP}/tenants/#{TENANT}/admin-invitations").to_return(status: 200, body: { invitations: [] }.to_json)
    get tenant_admin_invitations_path(TENANT)
    key = css_select("input[name=idempotency_key]").first["value"]
    post tenant_occasion_admin_invitations_path(TENANT, TENANT), params: { email: "prospect@example.test", idempotency_key: key }
    assert_redirected_to tenant_occasion_admin_invitations_path(TENANT, TENANT)
    assert_not_requested :post, "#{EP}/tenants/#{TENANT}/occasions/#{TENANT}/admin-invitations"
  end
end
