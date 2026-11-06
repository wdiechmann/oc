require "test_helper"
class JournalsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  PID = "ad763842-2538-4ccb-8445-17e232c37d84"
  QID = "ed763842-2538-4ccb-8445-17e232c37d84"
  JID = "bd763842-2538-4ccb-8445-17e232c37d84"
  RID = "cd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
    stub_request(:get, api).to_return(status: 200, body: data.to_json)
    stub_request(:get, "#{api}/reviews/#{RID}").to_return(status: 200, body: review.to_json)
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/journals"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/journals"
  def contexts = { setup_version: 5, period_version: 2, book_version: 1, base_currency: "DKK", accounting_authority: "ep" }
  def accounts = [ { id: PID, number: "0010", name: "Purchases", active: true }, { id: QID, number: "0020", name: "Bank", active: true } ]
  def lines = [ { id: nil, account_id: PID, reference: "", debit_minor: 10000, credit_minor: 0, vat_entry_id: nil, net_minor: nil, assessed_vat_minor: nil }, { id: nil, account_id: QID, reference: "", debit_minor: 0, credit_minor: 10000, vat_entry_id: nil, net_minor: nil, assessed_vat_minor: nil } ]
  def journal = { name: "Invoice", posting_date: "2026-06-01", reference: "INV-1", lines: lines }
  def validation = { status: "prepared", debit_minor: 10000, credit_minor: 10000, difference_minor: 0, balanced: true, errors: [], vat_complete: true, reporting: {}, period: { name: "2026", status: "open", version: 2 }, lines: lines.each_with_index.map { |l, i| { id: l[:id], account: accounts[i], errors: [], warnings: [], vat: nil } } }
  def data = { tenant_id: TID, book_id: BID, book_name: "Draft book", book_status: "draft", base_currency: "DKK", accounting_authority: "ep", status: "ready", source_version: 0, latest_version: 0, contexts: contexts, permissions: { prepare: true }, drafts: [], accounts: accounts, vat_entries: [], selected: nil }
  def review = { review_id: RID, expected_version: 0, digest: "digest", expires_at: 1.hour.from_now.iso8601, accepted_command_id: nil, plan: { draft_id: nil, expected_draft_version: nil, contexts: contexts, data: journal, validation: validation, before: nil } }
  def draft = { draft_id: "", expected_draft_version: "", expected_version: "0", contexts: contexts.transform_values(&:to_s), name: "Invoice", posting_date: "2026-06-01", reference: "INV-1", lines: lines.each_with_index.to_h { |l, i| [ i.to_s, l.transform_values { |v| v.nil? ? "" : v.to_s } ] } }
  def token = css_select("#accept-journal input[name=form_token]").first["value"]
  test "drafts require review and signed pointer acceptance with exact minor units" do
    get "#{path}/new"
    assert_response :success
    assert_select "#journal-editor fieldset", count: 2
    attrs = { draft_id: nil, expected_draft_version: nil, expected_version: 0, contexts: contexts, data: journal }
    command = stub_request(:post, "#{api}/reviews").with(body: attrs).to_return(status: 200, body: review.to_json)
    post "#{path}/review", params: draft
    assert_redirected_to "#{path}?review_id=#{RID}"
    assert_requested command
    follow_redirect!
    assert_includes response.body, "Debit 10000 · Credit 10000 · Difference 0"
    assert_includes response.body, "Unposted draft"
    stub_request(:post, "#{api}/accept").with(body: { review_id: RID, digest: "digest", expected_version: 0 }).to_return(status: 200, body: { stream_version: 1, draft_id: JID }.to_json)
    patch path, params: { form_token: token, debit_minor: "99", expected_version: "99" }
    assert_redirected_to "#{path}?draft_id=#{JID}"
  end
  test "issues may be explicitly saved; adding lines and amount errors retain the draft" do
    post "#{path}/review", params: draft.merge(intent: "add_line")
    assert_response :success
    assert_select "#journal-editor fieldset", count: 3
    stub_request(:post, "#{api}/reviews").to_return(status: 422, body: { error: "invalid_amount" }.to_json)
    modified = draft.deep_dup
    modified[:lines]["0"][:debit_minor] = "1.25"
    post "#{path}/review", params: modified
    assert_response :unprocessable_entity
    assert_select "input[name='lines[0][debit_minor]'][value='1.25']"
    bad = review.deep_dup
    bad[:plan][:validation] = validation.merge(status: "needs_attention", difference_minor: 100, errors: [ "journal_unbalanced", "period_not_open" ])
    stub_request(:get, "#{api}/reviews/#{RID}").to_return(status: 200, body: bad.to_json)
    get path, params: { review_id: RID }
    assert_includes response.body, "Debit and credit totals differ"
    assert_select "input[type=submit][value='Save draft with issues']"
  end
  test "unknown acceptance recovers the unchanged small pointer rather than financial form data" do
    get path, params: { review_id: RID }
    t = token
    key = Rails.application.message_verifier(:finance_setup).verified(t, purpose: :finance_setup).fetch("key")
    command = stub_request(:post, "#{api}/accept").with(body: { review_id: RID, digest: "digest", expected_version: 0 }, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: { form_token: t }
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceJournalDraft:save", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    assert_select "form[action='#{path}/retry']"
    command.to_return(status: 200, body: { stream_version: 1, draft_id: JID }.to_json)
    post "#{path}/retry", params: { expected_version: "99" }
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command, times: 2
  end
  test "context conflicts preserve line inputs and unavailable saved choices remain explicit" do
    stub_request(:post, "#{api}/reviews").to_return(status: 409, body: { error: "version_conflict" }.to_json)
    post "#{path}/review", params: draft
    assert_response :conflict
    assert_select "input[name='lines[0][debit_minor]'][value='10000']"
    assert_includes response.body, "periods changed"
    saved = { id: JID, data: journal, version: 1, contexts: contexts, validation: validation, history: [] }
    stub_request(:get, api).with(query: { draft_id: JID }).to_return(status: 200, body: data.merge(selected: saved, accounts: [], validation_stale: true).to_json)
    get path, params: { draft_id: JID, edit: "1" }
    assert_select "select[name='lines[0][account_id]'] option[value='#{PID}'][selected]", text: /Unavailable.*Purchases/
  end
  test "readonly, pending and revoked states suppress edits and clear financial data" do
    stub_request(:get, api).to_return(status: 200, body: data.merge(permissions: { prepare: false }).to_json)
    get path
    assert_select "#journal-editor", count: 0
    stub_request(:get, api).to_return(status: 200, body: data.merge(status: "pending").to_json)
    get path
    assert_select "#journal-editor", count: 0
    stub_request(:get, api).to_return(status: 404, body: { error: "not_found" }.to_json)
    get path
    assert_response :not_found
    assert_not_includes response.body, "Purchases"
  end
  test "pending review keeps readable unsaved entries without enabling acceptance" do
    stub_request(:post, "#{api}/reviews").to_return(status: 409, body: { error: "view_pending" }.to_json)
    stub_request(:get, api).to_return(status: 200, body: data.merge(status: "pending").to_json)
    post "#{path}/review", params: draft
    assert_response :conflict
    assert_includes response.body, "Your unsaved draft"
    assert_includes response.body, "Debit 10000"
    assert_includes response.body, "INV-1"
    assert_select "#accept-journal", count: 0
    assert_select "#journal-editor", count: 0
  end
end
