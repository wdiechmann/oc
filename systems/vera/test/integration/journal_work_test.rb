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
    { work_rows_enabled: true, tenant_id: TID, book_id: BID, book_name: "Book", book_status: "draft", base_currency: "DKK", accounting_authority: "ep", status: "ready", source_version: 1, latest_version: 1, contexts: contexts, permissions: { prepare: true }, drafts: [], accounts: [ { id: PID, number: "0010", name: "Purchases", active: true }, { id: QID, number: "0020", name: "Bank", active: true } ], vat_entries: [], selected: { id: JID, version: 1, contexts: contexts, data: { name: "Work journal", posting_date: "2026-06-01", reference: "INV", rows: [ { id: "cd763842-2538-4ccb-8445-17e232c37d84", posting_id: 1, reference: "", credit_total_minor: 0, credit_amount_minor: nil, amount_minor: 0, amount_basis: nil, basis_override: false, void: false } ] }, validation: { lines: [] } } }
  end
  def view(d = data)
    stub_request(:get, api).with(query: { draft_id: JID }).to_return(status: 200, body: d.to_json)
  end
  def token(form) = css_select("#{form} input[name=form_token]").first["value"]
  def row_form(t)
    { form_token: t, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s), reference: "Receipt", amount: "125,50", amount_basis: "gross", debit_account_id: PID, credit_account_id: QID, debit_label: "0010 · Purchases", credit_label: "0020 · Bank" }
  end
  test "metadata creates a work journal with its initial numbered line" do
    stub_request(:get, api).to_return(status: 200, body: data.merge(selected: nil).to_json)
    get "#{path}/new", headers: { "Accept-Language"=>"da-DK" }
    assert_select "#journal-create"
    assert_select "input[name=name]"
    assert_select "input[name=posting_date]"
    assert_select "input[name=reference]"
    assert_select "[data-work-row]", count: 0
    command = stub_request(:post, "#{api}/work/create").with(body: { initial_row: true, expected_version: 1, contexts: contexts, data: { name: "Draft", posting_date: "2026-06-01", reference: "INV" } }).to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
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
    command = stub_request(:post, "#{api}/work/row").with { |request| JSON.parse(request.body).dig("row", "credit_amount_minor") == -90000 && JSON.parse(request.body).dig("row", "amount_minor") == -112500 }.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: row_form(token("#work-row-new")).merge(amount: "-1125,00", credit_override: "true", credit_amount: "-900,00")
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command
  end
  test "posting ID leads the grid and the new row precedes saved rows newest first" do
    d = data
    d[:selected][:data][:rows] = [ 1, 2 ].map { |n| { id: "row#{n}", posting_id: n, reference: "Line #{n}", amount_minor: 10000, amount_basis: "gross", credit_total_minor: 10000, void: false } }
    view(d)
    get path, params: { draft_id: JID }
    assert_equal [ "work-row-row2", "work-row-row1" ], css_select("[data-work-row]").map { |form| form["id"] }
    columns = css_select("#work-row-row2 > :not(input)")
    assert_equal "2", columns.first.text
    assert columns[5].at_css("[data-work-included]")
    assert_equal "", columns[5].text.strip
    assert_includes columns[5].at_css("[data-work-included]")["title"], "apply VAT"
    assert_equal "0.00", columns[8].text
    assert_equal "No VAT configured", columns[8]["title"]
    assert_select "#main-content.w-full"
    assert_select "#main-content.max-w-6xl", count: 0
    assert columns[7].at_css("[data-work-credit].text-right")
    assert columns[4].at_css("[data-work-amount].text-right")
    assert columns[5].at_css("[data-work-included].ml-auto")
    assert_select ".journal-columns > .text-right", minimum: 4
    assert_select "#work-row-new input[type=submit][value='New line']"
    assert_equal "context-menu", columns[9].name
    assert columns[9].at_css("[data-menu-trigger] svg")
    assert_equal "menu", columns[9].at_css("[data-menu-trigger]")["aria-haspopup"]
    assert_equal "auto", columns[9].at_css("[role=menu]")["popover"]
    assert_equal [ "VAT operation", "Edit", "Void" ], columns[9].css("[role=menuitem]:not([hidden])").map(&:text)
    assert columns[9].at_css("[data-work-edit]").ancestors("[role=menu]").any?
    assert_select "#work-row-row2 [data-menu-trigger][aria-expanded=false]"
    assert_select "#work-row-row2 [role=menu] [data-work-save]", count: 1
  end
  test "Enter intent requests atomic save and next line" do
    view
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    command = stub_request(:post, "#{api}/work/row").with { |request| JSON.parse(request.body)["append_row"] == true }.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: row_form(token("#work-row-new")).merge(intent: "next_row")
    assert_redirected_to "#{path}?draft_id=#{JID}"
    assert_requested command
  end
  test "attachment picker review and binding render shared dialog streams and refresh journal fences" do
    rid = "cd763842-2538-4ccb-8445-17e232c37d84"
    upload_id = "dd763842-2538-4ccb-8445-17e232c37d84"
    info = { draft_id: JID, row_id: rid, posting_id: 1, attachments: [] }
    stub_request(:get, "#{api}/rows/#{rid}/attachments").to_return(status: 200, body: info.to_json)
    view
    headers = { "Accept"=>"text/vnd.turbo-stream.html" }
    get "#{path}/attachments", params: { row_id: rid }, headers: headers
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[target=shared-dialog-host] dialog[aria-labelledby=shared-dialog-title]"
    assert_select "input[type=file]"
    upload = { upload_id: upload_id, filename: "receipt.pdf", byte_size: 20 }
    stub_request(:post, "#{api}/rows/#{rid}/attachments/stage").to_return(status: 200, body: upload.to_json)
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\nSynthetic"), "application/pdf", original_filename: "receipt.pdf")
    post "#{path}/upload_attachment", params: { row_id: rid, file: file }, headers: headers
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #attach-enclosure"
    signed_token = token("#attach-enclosure")
    binding = stub_request(:post, "#{api}/work/attachment").to_timeout
    refreshed = data.merge(source_version: 2, latest_version: 2)
    refreshed[:selected][:version] = 2
    view(refreshed)
    patch path, params: { form_token: signed_token, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s) }, headers: headers
    assert_response :service_unavailable
    assert_select "turbo-stream[target=shared-dialog-host] a[href='#{path}/completion']"
    decoded = Rails.application.message_verifier(:finance_setup).verified(signed_token, purpose: :finance_setup)
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceJournalWork:attachment", idempotency_key: decoded.fetch("key") }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion", headers: headers
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] form[action='#{path}/retry']"
    binding.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    post "#{path}/retry", headers: headers
    assert_response :success
    assert_requested binding, times: 2
    assert_select "turbo-stream[target=vera-book-content][data-preserve-journal-draft] input[name=expected_draft_version][value='2']"
    assert_select "turbo-stream[target=shared-dialog-host] input[type=file]"
    assert_not_includes response.body, "<html"
  end
  test "saved complete posting preview shows all unposted legs and exact totals" do
    d=data
    d[:selected][:validation][:posting_preview]={ status: "complete", errors: [], debit_minor: 112500, credit_minor: 112500, difference_minor: 0, rows: [ { posting_id: 1, errors: [], legs: [ { role: "debit", account: { number: "0010", name: "Bank" }, debit_minor: 112500, credit_minor: 0 }, { role: "credit", account: { number: "0020", name: "Sales" }, debit_minor: 0, credit_minor: 90000 }, { role: "vat_input", account: { number: "6900", name: "Incoming VAT" }, debit_minor: 0, credit_minor: 22500 } ] } ] }
    view(d)
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    assert_select "#journal-posting-preview summary", text: "Saved posting preview · Unposted"
    assert_select "#journal-posting-preview tbody tr", count: 3
    assert_select "#journal-posting-preview td", text: "6900 · Incoming VAT"
    assert_select "#journal-posting-preview td", text: "225,00"
    assert_includes response.body, "Complete and balanced preview"
    assert_select "button", text: "Post journal", count: 0
  end
  test "saved row shows deductible VAT while retaining the full split on hover" do
    d=data
    row=d[:selected][:data][:rows].first
    row.merge!(amount_minor: 112500, credit_total_minor: 112500, posting_debit_minor: 101250, amount_basis: "gross", debit_account_id: PID, credit_account_id: QID, debit_line_id: "debit")
    d[:selected][:validation][:lines]=[ { id: "debit", vat: { code: "I25", posting_direction: "input", posting_vat_minor: 11250, amounts: { vat: 22500, deductible_vat: 11250, non_deductible_vat: 11250 } } } ]
    view(d)
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    assert_select "[data-work-credit][value='1125,00']"
    assert_select "[data-work-vat]", text: "112,50"
    assert_includes css_select("[data-work-vat]").first["title"], "225,00 total VAT"
    assert_includes css_select("[data-work-vat]").first["title"], "112,50 non-deductible"
  end
  test "money punctuation is strict and never uses floating point" do
    assert_equal ",", JournalMoney.separator("da-DK,da;q=0.9")
    assert_equal ".", JournalMoney.separator("en-GB")
    assert_equal ".", JournalMoney.separator("es-US")
    assert_equal 123450, JournalMoney.parse("1234,50", separator: ",")
    assert_equal 12550, JournalMoney.parse("125.50", separator: ".")
    assert_equal(-112500, JournalMoney.parse("-1125,00", separator: ",", signed: true))
    assert_equal(-112500, JournalMoney.parse("−1125.00", separator: ".", signed: true))
    assert_nil JournalMoney.parse("-1125,00", separator: ",")
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
  test "journal row keeps the VAT debit credit sign supplied by EP for income expense and refunds" do
    [ [ 125000, 100000, -25000, "output", "−250,00" ], [ 50000, 62500, 12500, "input", "125,00" ], [ 100000, 125000, 25000, "output", "250,00" ] ].each do |debit, credit, vat, direction, expected|
      d=data
      row=d[:selected][:data][:rows].first
      row.merge!(amount_minor: debit, credit_total_minor: credit, debit_line_id: "tax-source")
      d[:selected][:validation][:lines]=[ { id: "tax-source", vat: { code: "VAT25", posting_direction: direction, posting_vat_minor: vat, amounts: { vat: vat.abs, deductible_vat: vat.abs, non_deductible_vat: 0 } } } ]
      view(d)
      get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
      assert_select "[data-work-credit][value='#{JournalMoney.format(credit, separator: ',')}']"
      assert_select "[data-work-vat]", text: expected
    end
  end
  test "apply VAT is a separate flag and the operation dialog previews without saving" do
    view
    get path, params: { draft_id: JID }
    assert_select "input[name=vat_enabled]"
    assert_select "button[data-work-vat-operation]", text: "VAT operation"
    quote={ code: "I25", rate_bps: 2500, amounts: { net: 50000, vat: 12500 } }
    result={ row: { amount_minor: 50000, credit_total_minor: 62500, vat_enabled: true, posting_id: 8 }, validation: { lines: [ { vat: quote } ], posting_preview: { rows: [ { legs: [ { account: { number: "2000", name: "Expenses" }, debit_minor: 50000, credit_minor: 0 }, { account: { number: "63000", name: "Bank" }, debit_minor: 0, credit_minor: 62500 } ] } ] } } }
    preview=stub_request(:post, "#{api}/row-preview").with { |r| JSON.parse(r.body).dig("row", "vat_enabled")==true && JSON.parse(r.body).dig("row", "amount_minor")==50000 }.to_return(status: 200, body: result.to_json)
    post "#{path}/vat_operation", params: row_form(nil).merge(row_id: "", amount: "500,00", vat_enabled: "true"), headers: { "Accept-Language"=>"da-DK", "Accept"=>"text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #shared-dialog-title", text: "VAT operation · ID 8"
    assert_select "td", text: "500,00"
    assert_select "td", text: "625,00"
    assert_requested preview
    assert_not_requested :post, "#{api}/work/row"
  end
  test "dialog VAT selection streams a row draft and survives normal row save" do
    view
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    rid=data[:selected][:data][:rows].first[:id]
    t=token("#work-row-#{rid}")
    result={ row: { id: rid, amount_minor: 50000, credit_total_minor: 55000, vat_enabled: true, vat_entry_id: QID, vat_source_side: "debit" }, vat_options: [ { vat_entry_id: QID, code: "I10", name: "Alternate", rate_bps: 1000 } ], validation: { lines: [ { vat: { code: "I10", rate_bps: 1000, posting_vat_minor: 5000, amounts: { net: 50000, vat: 5000 } } } ], posting_preview: { rows: [], errors: [] } } }
    preview=stub_request(:post, "#{api}/row-preview").with { |r| JSON.parse(r.body).dig("row", "vat_entry_id")==QID && JSON.parse(r.body).dig("row", "vat_source_side")=="debit" }.to_return(status: 200, body: result.to_json)
    params=row_form(nil).merge(row_id: rid, amount: "500,00", vat_enabled: "true", vat_entry_id: QID, vat_source_side: "debit", intent: "apply_vat")
    post "#{path}/vat_operation", params: params, headers: { "Accept-Language"=>"da-DK", "Accept"=>"text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "select[name=vat_entry_id] option[value='#{QID}'][selected]"
    assert_select "turbo-stream[target='vat-operation-row-#{rid}'] journal-vat-update", count: 1
    patch=JSON.parse(css_select("journal-vat-update").first["data-patch"])
    assert_equal "550,00", patch["credit"]
    assert_equal "50,00", patch["vat"]
    assert_equal QID, patch["entry"]
    assert_requested preview
    assert_not_requested :post, "#{api}/work/row"
    command=stub_request(:post, "#{api}/work/row").with { |r| JSON.parse(r.body).dig("row", "vat_entry_id")==QID }.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: params.except(:intent).merge(form_token: t), headers: { "Accept-Language"=>"da-DK" }
    assert_response :see_other
    assert_requested command
  end
  test "journal index has links while details postings and preview stay on the journal page" do
    d=data
    d[:drafts]=[ d[:selected] ]
    stub_request(:get, api).to_return(status: 200, body: d.to_json)
    view(d)
    get path
    assert_response :success
    assert_select "h1", text: "Journals"
    assert_select "a[href='#{path}?draft_id=#{JID}']", text: "Work journal"
    assert_select "a[href='#{path}/new']", text: "New journal"
    assert_select "#journal-create, [data-work-row], #journal-posting-preview, [data-journal-details]", count: 0
    get path, params: { draft_id: JID }
    assert_response :success
    assert_select "h1", text: "Work journal"
    assert_select "a[href='#{path}']", text: "← Journals"
    assert_select "[data-journal-details]", count: 1
    assert_select "[data-work-row]", count: 1
    assert_select "#journal-create", count: 0
    assert_select "a[href='#{path}/new']", count: 0
    assert_select "a[href='#{path}?draft_id=#{JID}']", text: "Work journal", count: 0
    get "#{path}/new"
    assert_response :success
    assert_select "h1", text: "New journal"
    assert_select "#journal-create", count: 1
    assert_select "[data-work-row], #journal-posting-preview", count: 0
    assert_not_requested :post, "#{api}/work/create"
  end
end
