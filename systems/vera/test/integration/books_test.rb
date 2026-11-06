require "test_helper"
class BooksTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  STREAM = { "Accept"=>"text/vnd.turbo-stream.html" }
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def book
    { "book_id"=>BID, "tenant_id"=>TID, "parent_book_id"=>nil, "name"=>"SL2030", "code"=>"SL2030", "base_currency"=>"DKK", "accounting_authority"=>"ep", "timezone"=>"Europe/Copenhagen", "fiscal_year_start_month"=>1, "status"=>"draft", "version"=>1 }
  end
  def views
    stub_request(:get, "#{EP}/tenants/#{TID}/finance/books").to_return(status: 200, body: { tenant_id: TID, tenant_name: "Spejdernes Lejr", status: "ready", books: [ book ], source_version: 1, latest_version: 1 }.to_json)
    stub_request(:get, "#{EP}/tenants/#{TID}/finance/books/#{BID}").to_return(status: 200, body: { tenant_id: TID, status: "ready", book: book, expected_version: 1 }.to_json)
  end
  test "list and create a book through EP with an idempotency key" do
    views
    get "/tenants/#{TID}/books"
    assert_response :success
    assert_includes response.body, "Spejdernes Lejr"
    get "/tenants/#{TID}/books/new"
    assert_response :success
    key = css_select("input[name=idempotency_key]").first["value"]
    created = stub_request(:post, "#{EP}/tenants/#{TID}/finance/books").with(headers: { "Idempotency-Key"=>key }, body: { name: "New book", code: "NEW", base_currency: "DKK", accounting_authority: "ep", timezone: "Europe/Copenhagen", fiscal_year_start_month: 1, parent_book_id: nil }.to_json).to_return(status: 200, body: { book_id: BID, stream_version: 2 }.to_json)
    post "/tenants/#{TID}/books", params: { name: "New book", code: "NEW", base_currency: "DKK", accounting_authority: "ep", timezone: "Europe/Copenhagen", fiscal_year_start_month: "1", parent_book_id: "", idempotency_key: key }
    assert_redirected_to "/tenants/#{TID}/books/#{BID}"
    assert_requested created
  end
  test "stale edits return inline conflict feedback without replaying a mutation" do
    views
    get "/tenants/#{TID}/books/#{BID}"
    assert_select "#book-header-actions [role=menuitem]", text: "Refresh book"
    assert_select "#book-header-actions a[data-turbo-stream]", text: "Edit name and hierarchy"
    assert_select "input[name=idempotency_key]", count: 0
    get "/tenants/#{TID}/books/#{BID}/edit_dialog", headers: STREAM
    assert_select "turbo-stream[target=shared-dialog-host] form"
    key = css_select("input[name=idempotency_key]").first["value"]
    edit = stub_request(:patch, "#{EP}/tenants/#{TID}/finance/books/#{BID}").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch "/tenants/#{TID}/books/#{BID}", params: { name: "My draft", parent_book_id: "", expected_version: "1", idempotency_key: key }, headers: STREAM
    assert_response :conflict
    assert_select "turbo-stream[target=vera-feedback]"
    assert_includes response.body, "newer revision"
    assert_requested edit, times: 1
  end
  test "lost response can be checked by original key with no repeated create" do
    views
    get "/tenants/#{TID}/books/new"
    key = css_select("input[name=idempotency_key]").first["value"]
    create = stub_request(:post, "#{EP}/tenants/#{TID}/finance/books").to_timeout
    post "/tenants/#{TID}/books", params: { name: "New", code: "NEW", base_currency: "DKK", accounting_authority: "ep", timezone: "Europe/Copenhagen", fiscal_year_start_month: "1", idempotency_key: key }, headers: STREAM
    assert_response :service_unavailable
    assert_includes response.body, "Check completion"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceBookCreate", idempotency_key: key }).to_return(status: 200, body: { status: "accepted", result: { book_id: BID } }.to_json)
    get "/tenants/#{TID}/books/completion"
    assert_redirected_to "/tenants/#{TID}/books/#{BID}"
    assert_requested create, times: 1
  end
  test "revoked access removes the protected book region on a streamed save" do
    views
    get "/tenants/#{TID}/books/#{BID}"
    assert_select "#book-header-actions [role=menuitem]", text: "Refresh book"
    assert_select "#book-header-actions a[data-turbo-stream]", text: "Edit name and hierarchy"
    assert_select "input[name=idempotency_key]", count: 0
    get "/tenants/#{TID}/books/#{BID}/edit_dialog", headers: STREAM
    assert_select "turbo-stream[target=shared-dialog-host] form"
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:patch, "#{EP}/tenants/#{TID}/finance/books/#{BID}").to_return(status: 404, body: { error: "not_found" }.to_json)
    patch "/tenants/#{TID}/books/#{BID}", params: { name: "Private draft", parent_book_id: "", expected_version: "1", idempotency_key: key }, headers: STREAM
    assert_response :not_found
    assert_select "turbo-stream[target=vera-book-content]"
    assert_not_includes response.body, "Private draft"
  end

  test "a pending projection shows its state and does not enable stale editing" do
    views
    stub_request(:get, "#{EP}/tenants/#{TID}/finance/books/#{BID}").to_return(status: 200, body: { tenant_id: TID, book_id: BID, status: "pending", book: nil, expected_version: 2 }.to_json)
    get "/tenants/#{TID}/books/#{BID}"
    assert_response :success
    assert_includes response.body, "view is updating"
    assert_select "input[name=expected_version]", count: 0
  end
  test "unknown receipt checks update feedback without discarding the submitted form" do
    views
    get "/tenants/#{TID}/books/new"
    key = css_select("input[name=idempotency_key]").first["value"]
    stub_request(:post, "#{EP}/tenants/#{TID}/finance/books").to_timeout
    post "/tenants/#{TID}/books", params: { name: "Keep draft", code: "KEEP", base_currency: "DKK", accounting_authority: "ep", timezone: "Europe/Copenhagen", fiscal_year_start_month: "1", idempotency_key: key }, headers: STREAM
    assert_select "a[data-turbo-stream]", text: "Check completion"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceBookCreate", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "/tenants/#{TID}/books/completion", headers: STREAM
    assert_response :success
    assert_select "turbo-stream[target=vera-feedback]"
    assert_includes response.body, "outcome is still unknown"
    assert_select "turbo-stream[target=vera-book-content]", count: 0
  end
end
