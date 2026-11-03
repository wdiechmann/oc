require "test_helper"

class ChartOrdersTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  RID = "bd763842-2538-4ccb-8445-17e232c37d84"
  AID = "ad763842-2538-4ccb-8445-17e232c37d84"
  CID = "cd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/chart_order"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/chart-order"
  def info
    { tenant_id: TID, book_id: BID, book_name: "Order book", source_version: 8, rows: [ { id: AID, number: "0010", name: "Bank", kind: "posting", position: 10, active: true }, { id: CID, number: nil, name: "Total", kind: "calculation", position: 20, active: true } ] }
  end
  def review
    { tenant_id: TID, book_id: BID, book_name: "Order book", review_id: RID, expected_version: 8, digest: "review-digest", expires_at: 1.hour.from_now.iso8601, plan: { changed_count: 2, row_count: 2, rows: [ { account_id: CID, number: nil, name: "Total", kind: "calculation", before_position: 20, after_position: 100, changed: true }, { account_id: AID, number: "0010", name: "Bank", kind: "posting", before_position: 10, after_position: 200, changed: true } ] } }
  end
  def review_token
    stub_request(:get, "#{api}/reviews/#{RID}").to_return(status: 200, body: review.to_json)
    get path, params: { review_id: RID }
    assert_response :success
    css_select("input[name=form_token]").first["value"]
  end

  test "complete-chart editor renders native movement and rebalance controls" do
    stub_request(:get, api).to_return(status: 200, body: info.to_json)
    get path
    assert_response :success
    assert_select "chart-order-editor li[data-order-row]", count: 2
    assert_equal [ AID, CID ], css_select("input[name='ordered_ids[]']").map { |input| input["value"] }
    assert_select "[data-order-move=before]", text: "Move before"
    assert_select "input[value='Review position rebalance']"
    assert_select "script[src*=chart_order_editor]"
    assert_not_requested :post, "#{api}/reviews"
  end

  test "preview sends only a complete order and source revision, then renders the private review" do
    preview = stub_request(:post, "#{api}/reviews").with(body: { ordered_ids: [ CID, AID ], expected_version: 8 }).to_return(status: 200, body: review.to_json)
    stub_request(:get, "#{api}/reviews/#{RID}").to_return(status: 200, body: review.to_json)
    post "#{path}/preview", params: { ordered_ids: [ CID, AID ], expected_version: "8", name: "Ignored" }
    assert_redirected_to "#{path}?review_id=#{RID}"
    follow_redirect!
    assert_select "h1", text: "Review chart order"
    assert_includes response.body, "2 positions change"
    assert_select "input[value='Accept reviewed order']"
    assert_requested preview
    assert_not_requested :post, "#{api}/reviews/#{RID}/accept"
  end

  test "acceptance uses the signed reviewed pointer, never replacement order/body fields" do
    token = review_token
    accept = stub_request(:post, "#{api}/reviews/#{RID}/accept").with(body: { digest: "review-digest", expected_version: 8 }, headers: { "Idempotency-Key"=>/\A[0-9a-f-]{36}\z/ }).to_return(status: 200, body: { stream_version: 10 }.to_json)
    patch path, params: { form_token: token, digest: "tampered", expected_version: 100, ordered_ids: [ AID, CID ], review_id: BID }
    assert_redirected_to "/tenants/#{TID}/books/#{BID}/chart"
    assert_requested accept
    patch path, params: { form_token: "tampered" }
    assert_response :unprocessable_entity
    assert_requested accept, times: 1
  end

  test "unknown outcomes block new previews and explicit retries preserve original review and key" do
    token = review_token
    key = Rails.application.message_verifier(:finance_setup).verified(token, purpose: :finance_setup).fetch("key")
    accept = stub_request(:post, "#{api}/reviews/#{RID}/accept").with(body: { digest: "review-digest", expected_version: 8 }, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: { form_token: token }
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    post "#{path}/preview", params: { ordered_ids: [ AID, CID ], expected_version: 8 }
    assert_not_requested :post, "#{api}/reviews"
    post "#{path}/retry"
    assert_response :unprocessable_entity
    assert_requested accept, times: 1
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceChartOrder:accept", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    assert_select "form[action='#{path}/retry']"
    accept.to_return(status: 200, body: { stream_version: 10 }.to_json)
    post "#{path}/retry", params: { ordered_ids: [ AID, CID ], expected_version: 99 }
    assert_redirected_to "/tenants/#{TID}/books/#{BID}/chart"
    assert_requested accept, times: 2
  end

  test "stale reviews require a fresh order, and revoked access removes protected rows" do
    stub_request(:post, "#{api}/reviews").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    post "#{path}/preview", params: { ordered_ids: [ AID, CID ], expected_version: 8 }
    assert_response :conflict
    assert_select "a[href='#{path}']", text: "Open current chart order"
    stub_request(:get, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    get path
    assert_response :not_found
    assert_not_includes response.body, "Bank"
    assert_select "input[name='ordered_ids[]']", count: 0
  end
  test "unavailable preview reports no accepted position changes" do
    stub_request(:post, "#{api}/reviews").to_timeout
    post "#{path}/preview", params: { ordered_ids: [ AID, CID ], expected_version: 8 }
    assert_response :service_unavailable
    assert_includes response.body, "No account positions were changed"
    assert_select "a", text: "Check completion", count: 0
  end
end
