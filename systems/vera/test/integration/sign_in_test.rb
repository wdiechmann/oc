require "test_helper"

class SignInTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    Mail::TestMailer.deliveries.clear
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }

  def sign_in
    stub_request(:post, "#{EP}/auth/magic-links/verify").with(body: { token: "a"*43 }.to_json).to_return(status: 200, body: { token: "private-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    assert_redirected_to "/session/confirm"
    post "/session"
    assert_redirected_to "/"
  end

  test "requesting sign-in uses existing-only EP flow and delivers a VERA link" do
    get "/session/new"
    assert_response :success
    issued = stub_request(:post, "#{EP}/auth/sign-in-links").with(headers: { "X-EP-Backend-Token"=>"v"*48 }, body: { email: "member@example.test" }.to_json).to_return(status: 202, body: { delivery: { email: "member@example.test", token: "a"*43, expires_at: 15.minutes.from_now.iso8601 } }.to_json)
    post "/session/link", params: { email: "member@example.test" }
    assert_redirected_to "/session/new"
    assert_requested issued
    assert_equal 1, Mail::TestMailer.deliveries.size
    assert_includes Mail::TestMailer.deliveries.last.body.decoded, "/session/verify?token="
    assert_not_requested :post, "#{EP}/auth/magic-links"
    follow_redirect!
    assert_not_includes response.body, "a"*43
    assert_select "[role=status] a[href*='/session/verify?token=']", count: 0
  end

  test "unknown or throttled identities get the same generic response without delivery" do
    stub_request(:post, "#{EP}/auth/sign-in-links").to_return(status: 202, body: { delivery: nil }.to_json)
    post "/session/link", params: { email: "unknown@example.test" }
    assert_redirected_to "/session/new"
    follow_redirect!
    assert_includes response.body, "If your identity is registered"
    assert_empty Mail::TestMailer.deliveries
  end

  test "GET link verification never redeems the challenge and confirmation stores a private session" do
    get "/session/verify", params: { token: "a"*43 }
    assert_redirected_to "/session/confirm"
    get "/session/confirm"
    assert_response :success
    assert_not_includes response.body, "a"*43
    assert_not_requested :post, "#{EP}/auth/magic-links/verify"
    sign_in
    stub_request(:get, "#{EP}/me/workspaces").with(headers: { "Authorization"=>"Bearer private-session" }).to_return(status: 200, body: { tenants: [ { tenant_id: SecureRandom.uuid, name: "My camp" } ], occasions: [] }.to_json)
    get "/"
    assert_response :success
    assert_includes response.body, "My camp"
    assert_not_includes response.body, "private-session"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "workspace has separate Tenant and Occasion columns with direct book links" do
    sign_in
    tid, bid, oid = SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid
    payload = { tenants: [ { tenant_id: tid, name: "My tenant" } ], occasions: [ { tenant_id: tid, occasion_id: oid, tenant_name: "My tenant", name: "Summer camp", book_id: bid, book_name: "Camp book" } ], finance_books: [ { tenant_id: tid, tenant_name: "My tenant", book_id: bid, name: "Camp book" } ] }
    stub_request(:get, "#{EP}/me/workspaces").to_return(status: 200, body: payload.to_json)
    get "/"
    assert_select "#workspace-tenants-title", text: "Tenant"
    assert_select "#workspace-occasions-title", text: "Occasion"
    assert_select "section[aria-labelledby=workspace-occasions-title] a[href='/tenants/#{tid}/books/#{bid}']", text: "Open book · Camp book"
    assert_select "a[href$='/setup']", count: 0
    assert_select "section[aria-labelledby=workspace-tenants-title] article", count: 1
  end

  test "logout revokes this EP session and removes local access" do
    sign_in
    revoked = stub_request(:delete, "#{EP}/auth/session").with(headers: { "Authorization"=>"Bearer private-session" }).to_return(status: 200, body: { status: "signed_out" }.to_json)
    delete "/session"
    assert_redirected_to "/session/new"
    assert_requested revoked
    get "/"
    assert_response :success
    assert_select "a", text: "Sign in"
    assert_not_requested :get, "#{EP}/me/workspaces"
  end

  test "revoked sessions are cleared and EP outages preserve the sign-in form inline" do
    sign_in
    stub_request(:get, "#{EP}/me/workspaces").to_return(status: 401, body: { error: "unauthenticated" }.to_json)
    get "/"
    assert_redirected_to "/session/new"
    stub_request(:post, "#{EP}/auth/sign-in-links").to_timeout
    post "/session/link", params: { email: "member@example.test" }, headers: { "Accept"=>"text/vnd.turbo-stream.html" }
    assert_response :service_unavailable
    assert_select "turbo-stream[target=vera-feedback]"
    assert_not_includes response.body, "member@example.test"
  end
  test "logout drops the browser session even if EP cannot confirm revocation" do
    sign_in
    stub_request(:delete, "#{EP}/auth/session").to_timeout
    delete "/session"
    assert_redirected_to "/session/new"
    follow_redirect!
    assert_includes response.body, "revocation was not confirmed"
    get "/"
    assert_select "a", text: "Sign in"
    assert_not_requested :get, "#{EP}/me/workspaces"
  end
  test "a replaced sign-in link is explained separately from an expired authenticated session" do
    get "/session/verify", params: { token: "a"*43 }
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 401, body: { error: "invalid_token" }.to_json)
    post "/session"
    assert_redirected_to "/session/new"
    follow_redirect!
    assert_includes response.body, "replaced by a newer request"
    assert_includes response.body, "newest VERA message"
    assert_not_includes response.body, "Your sign-in has expired"
    get "/session/confirm"
    assert_redirected_to "/session/new"
  end
  test "development sign-in link is clickable in the flash and consumed after one display" do
    stub_request(:post, "#{EP}/auth/sign-in-links").to_return(status: 202, body: { delivery: { email: "member@example.test", token: "a"*43, expires_at: 15.minutes.from_now.iso8601 } }.to_json)
    environment = Rails.env
    original = environment.method(:development?)
    environment.define_singleton_method(:development?) { true }
    begin
      post "/session/link", params: { email: "member@example.test" }
      follow_redirect!
      assert_select "[role=status] a[href*='/session/verify?token=']", text: "Sign in to VERA"
      assert_includes css_select("[role=status] a").first["href"], "a"*43
      get new_session_path
      assert_select "[role=status] a[href*='/session/verify?token=']", count: 0
      stub_request(:post, "#{EP}/auth/sign-in-links").to_return(status: 202, body: { delivery: nil }.to_json)
      post "/session/link", params: { email: "unknown@example.test" }
      follow_redirect!
      assert_select "[role=status] a[href*='/session/verify?token=']", count: 0
    ensure
      environment.define_singleton_method(:development?, original)
    end
  end
end
