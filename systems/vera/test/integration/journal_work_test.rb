require "test_helper"
class JournalWorkTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  PID = "ad763842-2538-4ccb-8445-17e232c37d84"
  QID = "ed763842-2538-4ccb-8445-17e232c37d84"
  JID = "bd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/journals"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}/journals"
  def contexts = { setup_version: 5, period_version: 2, book_version: 1, base_currency: "DKK", accounting_authority: "ep" }
  def data
    { work_rows_enabled: true, tenant_id: TID, book_id: BID, book_name: "Book", book_status: "draft", base_currency: "DKK", accounting_authority: "ep", status: "ready", source_version: 1, latest_version: 1, contexts: contexts, permissions: { prepare: true }, drafts: [], accounts: [ { id: PID, number: "0010", name: "Purchases", active: true }, { id: QID, number: "0020", name: "Bank", active: true } ], vat_entries: [], selected: { id: JID, version: 1, contexts: contexts, data: { name: "Work journal", posting_date: "2026-06-01", reference: "INV", rows: [] }, validation: { lines: [] } } }
  end
  def view(d = data)
    stub_request(:get, api).with(query: { draft_id: JID }).to_return(status: 200, body: d.to_json)
  end
  def token(form) = css_select("#{form} input[name=form_token]").first["value"]
  def row_form(t)
    { form_token: t, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s), reference: "Receipt", amount: "125,50", amount_basis: "gross", debit_account_id: PID, credit_account_id: QID, debit_label: "0010 · Purchases", credit_label: "0020 · Bank" }
  end
  test "metadata creates a work journal before any row or number exists" do
    stub_request(:get, api).to_return(status: 200, body: data.merge(selected: nil).to_json)
    get path, headers: { "Accept-Language"=>"da-DK" }
    assert_select "#journal-create"
    assert_select "input[name=name]"
    assert_select "input[name=posting_date]"
    assert_select "input[name=reference]"
    assert_select "[data-work-row]", count: 0
    command = stub_request(:post, "#{api}/work/create").with(body: { expected_version: 1, contexts: contexts, data: { name: "Draft", posting_date: "2026-06-01", reference: "INV" } }).to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: { form_token: token("#journal-create"), name: "Draft", posting_date: "2026-06-01", reference: "INV", expected_version: "1", contexts: contexts.transform_values(&:to_s) }
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command
    view(data.merge(status: "pending", selected: nil))
    get path, params: { draft_id: JID }
    assert_select "journal-work-editor[data-pending=true]", count: 1
    assert_select "#journal-create", count: 0
  end
  test "paired row saves comma amounts exactly and uses original key for receipt recovery" do
    view
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    assert_select "[role=combobox]", count: 2
    assert_select "input[data-work-included][type=checkbox]"
    assert_select "input[name=basis_override][value=false]"
    assert_select "select[name=amount_basis]", count: 0
    assert_select "input[name=amount][type=text][inputmode=decimal]"
    assert_select "input[name=credit_amount][type=text][inputmode=decimal]"
    assert_select "input[name=credit_override][value=false]"
    t = token("#work-row-new")
    key = Rails.application.message_verifier(:finance_setup).verified(t, purpose: :finance_setup).fetch("key")
    attrs = { expected_version: 1, contexts: contexts, draft_id: JID, expected_draft_version: 1, row: { id: nil, reference: "Receipt", debit_account_id: PID, credit_account_id: QID, amount_minor: 12550, credit_amount_minor: nil, amount_basis: "gross", basis_override: true, void: false } }
    command = stub_request(:post, "#{api}/work/row").with(body: attrs, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: row_form(t)
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceJournalWork:row", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    command.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    post "#{path}/retry"
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command, times: 2
  end
  test "manual credit amount uses locale parsing and remains an explicit override" do
    view
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    command = stub_request(:post, "#{api}/work/row").with { |request| JSON.parse(request.body).dig("row", "credit_amount_minor") == 15000 }.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: row_form(token("#work-row-new")).merge(credit_override: "true", credit_amount: "150,00")
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command
  end
  test "posting ID leads the grid and the new row precedes saved rows newest first" do
    d = data
    d[:selected][:data][:rows] = [ 1, 2 ].map { |n| { id: "row#{n}", posting_id: n, reference: "Line #{n}", amount_minor: 10000, amount_basis: "gross", credit_total_minor: 10000, void: false } }
    view(d)
    get path, params: { draft_id: JID }
    assert_equal [ "work-row-new", "work-row-row2", "work-row-row1" ], css_select("[data-work-row]").map { |form| form["id"] }
    columns = css_select("#work-row-row2 > :not(input)")
    assert_equal "2", columns.first.text
    assert columns[5].at_css("[data-work-included]")
    assert_equal "", columns[5].text.strip
    assert_includes columns[5].at_css("[data-work-included]")["title"], "VAT included"
    assert_equal "0.00", columns[8].text
    assert_equal "No VAT configured", columns[8]["title"]
    assert_select "#main-content.w-full"
    assert_select "#main-content.max-w-6xl", count: 0
    assert columns[7].at_css("[data-work-credit]")
    assert_equal "context-menu", columns[9].name
    assert columns[9].at_css("[data-menu-trigger] svg")
    assert_equal "menu", columns[9].at_css("[data-menu-trigger]")["aria-haspopup"]
    assert_equal "auto", columns[9].at_css("[role=menu]")["popover"]
    assert_equal [ "Edit", "Void" ], columns[9].css("[role=menuitem]:not([hidden])").map(&:text)
    assert columns[9].at_css("[data-work-edit]").ancestors("[role=menu]").any?
    assert_select "#work-row-new [data-menu-trigger][aria-expanded=false]"
    assert_select "#work-row-new [role=menu] [data-work-save]", count: 1
  end
  test "money punctuation is strict and never uses floating point" do
    assert_equal ",", JournalMoney.separator("da-DK,da;q=0.9")
    assert_equal ".", JournalMoney.separator("en-GB")
    assert_equal ".", JournalMoney.separator("es-US")
    assert_equal 123450, JournalMoney.parse("1234,50", separator: ",")
    assert_equal 12550, JournalMoney.parse("125.50", separator: ".")
    assert_nil JournalMoney.parse("1.234,50", separator: ",")
    assert_nil JournalMoney.parse("1.234", separator: ".")
    assert_nil JournalMoney.parse("125.50", separator: ",")
    assert_equal "125,50", JournalMoney.format(12550, separator: ",")
  end
  test "account lookup and VAT previews remain scoped read-only responses" do
    view
    stub_request(:get, "#{api}/accounts").with(query: { q: "001" }).to_return(status: 200, body: { source_version: 5, results: [ data[:accounts].first ] }.to_json)
    get "#{path}/accounts", params: { q: "001" }
    assert_response :success
    assert_equal "0010", response.parsed_body["results"][0]["number"]
    stub_request(:post, "#{api}/row-preview").to_return(status: 200, body: { validation: { lines: [] } }.to_json)
    post "#{path}/row_preview", params: row_form(nil).merge(row_id: ""), headers: { "Accept-Language"=>"da-DK" }
    assert_response :success
    stub_request(:get, "#{api}/accounts").with(query: { q: "x" }).to_return(status: 404, body: { error: "not_found" }.to_json)
    get "#{path}/accounts", params: { q: "x" }
    assert_response :not_found
    assert_not_includes response.body, "Purchases"
  end
end
