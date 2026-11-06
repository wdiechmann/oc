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
    assert_select "body > #vera-feedback.vera-toast-stack vera-toast [role=status]", text: "Journal draft saved. Continue working on its lines."
    assert_select "#main-content #vera-feedback", count: 0
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
    assert_select "#work-row-new[hidden]"
    assert_equal "New line", css_select("#journal-header-actions [role=menuitem]").first.text
    assert_select "#journal-header-actions button[type=submit][form=work-row-new]", text: "New line"
    assert_select ".journal-grid [type=submit][value='New line']", count: 0
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
    upload = { upload_id: upload_id, filename: "receipt.pdf", content_type: "application/pdf", byte_size: 20 }
    stub_request(:post, "#{api}/rows/#{rid}/attachments/stage").to_return(status: 200, body: upload.to_json)
    file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\nSynthetic"), "application/pdf", original_filename: "receipt.pdf")
    post "#{path}/upload_attachment", params: { row_id: rid, file: file }, headers: headers
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #attach-enclosure"
    assert_select "turbo-stream[target=shared-dialog-host] iframe[src*=preview_attachment][title='Preview of receipt.pdf']"
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
  test "attachment previews serve authenticated inline PDFs and images with private caching" do
    rid = "cd763842-2538-4ccb-8445-17e232c37d84"
    upload_id = "dd763842-2538-4ccb-8445-17e232c37d84"
    file = { filename: "receipt.pdf", content_type: "application/pdf", content: Base64.strict_encode64("%PDF-1.4 synthetic") }
    stub_request(:get, "#{api}/rows/#{rid}/attachments/stage/#{upload_id}").to_return(status: 200, body: file.to_json)
    get "#{path}/preview_attachment", params: { row_id: rid, upload_id: upload_id }
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers["Content-Disposition"], "inline"
    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    file = { filename: "receipt.png", content_type: "image/png", content: Base64.strict_encode64("synthetic image") }
    stub_request(:get, "#{api}/attachments/#{upload_id}").to_return(status: 200, body: file.to_json)
    get "#{path}/preview_attachment", params: { attachment_id: upload_id }
    assert_response :success
    assert_equal "image/png", response.media_type
    info = { draft_id: JID, row_id: rid, posting_id: 1, attachments: [ { id: upload_id, filename: "receipt.png", content_type: "image/png", byte_size: 15, sha256: "synthetic" } ] }
    stub_request(:get, "#{api}/rows/#{rid}/attachments").to_return(status: 200, body: info.to_json)
    view
    get "#{path}/attachments", params: { row_id: rid }, headers: { "Accept"=>"text/vnd.turbo-stream.html" }
    assert_select "details img[alt='Preview of receipt.png'][src*=preview_attachment]"
    assert_select "a[href*='download_attachment']", text: "receipt.png"
  end

  test "saved complete posting preview shows all unposted legs and exact totals" do
    d=data
    d[:selected][:validation][:posting_preview]={ status: "complete", errors: [], debit_minor: 112500, credit_minor: 112500, difference_minor: 0, rows: [ { posting_id: 1, errors: [], legs: [ { role: "debit", account: { number: "0010", name: "Bank" }, debit_minor: 112500, credit_minor: 0 }, { role: "credit", account: { number: "0020", name: "Sales" }, debit_minor: 0, credit_minor: 90000 }, { role: "vat_input", account: { number: "6900", name: "Incoming VAT" }, debit_minor: 0, credit_minor: 22500 } ] } ] }
    view(d)
    get path, params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK" }
    assert_select "#journal-posting-preview", count: 0
    assert_select "#journal-header-actions a", text: "Saved posting preview · Unposted"
    get "#{path}/posting_preview", params: { draft_id: JID }, headers: { "Accept-Language"=>"da-DK", "Accept"=>"text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #shared-dialog-title", text: "Saved posting preview · Unposted"
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
  test "journal row menu opens a summed posting dialog and posts only its signed reviewed plan" do
    plan = { tenant_id: TID, book_id: BID, draft_id: JID, name: "Work journal", posting_date: "2026-06-01", base_currency: "DKK", expected_version: 1, expected_draft_version: 1, contexts: contexts, digest: "reviewed-impact", can_post: true, errors: [], accounts: [ { account: { id: PID, number: "0010", name: "Purchases" }, prepost_minor: 10000, post_minor: 25000, postpost_minor: 35000 } ] }
    stub_request(:get, "#{api}/posting-impact").with(query: { draft_id: JID }).to_return(status: 200, body: plan.to_json)
    get "#{path}/post_dialog", params: { draft_id: JID }, headers: { "Accept"=>"text/vnd.turbo-stream.html", "Accept-Language"=>"da-DK" }
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] dialog.vera-post-dialog"
    assert_select "table[data-journal-impact] tbody tr", count: 1
    assert_select "thead th", text: "Prepost"
    assert_select "thead th", text: "Postpost"
    assert_select "tbody td", text: "350,00"
    assert_select "input[type=submit][value=Post]:not([disabled])"
    signed = css_select("input[name=form_token]").first["value"]
    command = stub_request(:post, "#{api}/work/post").with(body: plan.slice(:draft_id, :expected_version, :expected_draft_version, :contexts, :digest).to_json).to_return(status: 200, body: { draft_id: JID, stream_version: 2, posted: true }.to_json)
    patch path, params: { form_token: signed, draft_id: JID, expected_version: "999", digest: "tampered" }
    assert_redirected_to path
    assert_requested command
    plan[:errors] = [ "period_not_open" ]
    stub_request(:get, "#{api}/posting-impact").with(query: { draft_id: JID }).to_return(status: 200, body: plan.to_json)
    get "#{path}/post_dialog", params: { draft_id: JID }, headers: { "Accept"=>"text/vnd.turbo-stream.html" }
    assert_select "input[type=submit][value=Post][disabled]"
    assert_select "[role=alert]", text: "period not open"
    plan[:errors] = [ "account_required", "choose_one_nonzero_side" ]
    plan[:row_errors] = [ { posting_id: 8, row_id: "unfinished", errors: plan[:errors] } ]
    stub_request(:get, "#{api}/posting-impact").with(query: { draft_id: JID }).to_return(status: 200, body: plan.to_json)
    get "#{path}/post_dialog", params: { draft_id: JID }, headers: { "Accept"=>"text/vnd.turbo-stream.html" }
    assert_select "[role=alert]", count: 2
    assert_select "[role=alert]", text: "Posting ID 8: Select a posting account."
    assert_select "[role=alert]", text: "Posting ID 8: Enter a nonzero amount on the selected side."
    d=data
    d[:selected][:data][:posted] = true
    d[:drafts] = [ d[:selected] ]
    stub_request(:get, api).to_return(status: 200, body: d.to_json)
    view(d)
    get path
    assert_select "#journal-actions-#{JID} button[disabled]", text: "Post journal"
    assert_select "#journal-actions-#{JID} button[disabled]", text: "Delete journal"
    get path, params: { draft_id: JID }
    assert_select "#work-row-new", count: 0
    assert_select "input[name=amount][readonly]"
    assert_select "#journal-header-actions a", text: "Saved posting preview · Posted"
  end

  test "journal index has links while details postings and preview stay on the journal page" do
    d=data
    d[:drafts]=[ d[:selected] ]
    stub_request(:get, api).to_return(status: 200, body: d.to_json)
    view(d)
    get path
    assert_response :success
    assert_select "h1", text: "Journals"
    assert_select "#journal-actions-#{JID} a[role=menuitem][href='#{path}/post_dialog?draft_id=#{JID}']", text: "Post journal"
    assert_select "#journal-actions-#{JID} a[role=menuitem][href='#{path}/delete_dialog?draft_id=#{JID}']", text: "Delete journal"
    assert_select "a[href='#{path}?draft_id=#{JID}']", text: "Work journal"
    assert_select "#journals-index-actions a[href='#{path}/new'][role=menuitem]", text: "New journal"
    assert_select "#journals-index-actions a[href='#{path}'][role=menuitem]", text: "Refresh journals"
    assert_select "#journal-create, [data-work-row], #journal-posting-preview, [data-journal-details]", count: 0
    get path, params: { draft_id: JID }
    assert_response :success
    assert_select "h1", text: "Work journal"
    assert_select "a[href='#{path}']", text: "Back to journals"
    assert_select "[data-journal-details]", count: 0
    assert_select "#journal-header-actions [data-journal-details-link]", text: "Edit journal details"
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
  test "journal header menu replaces the standalone links and opens history and delete dialogs" do
    d=data
    d[:drafts]=[ d[:selected].merge(history: [ { version: 1, accepted_at: "2026-06-01", actor_identity_id: PID, application_id: "vera" } ]) ]
    view(d)
    get path, params: { draft_id: JID }
    assert_select "header h1", text: "Work journal"
    assert_select "#journal-header-actions [role=menuitem]", text: "Back to journals"
    assert_select "#journal-header-actions [role=menuitem]", text: "Delete journal"
    assert_select "#journal-header-actions [role=menuitem]", text: "Show history"
    assert_select "#journal-header-actions [role=menuitem]", text: "Refresh journal"
    assert_select "a", text: "← Journals", count: 0
    assert_select "summary", text: /Revision history/, count: 0
    get "#{path}/history", params: { draft_id: JID }, as: :turbo_stream
    assert_response :success
    assert_select "#shared-dialog-title", text: "Journal history · Work journal"
    assert_select "a[href='#{path}?draft_id=#{JID}&version=1']", text: "Revision 1"
    get "#{path}/delete_dialog", params: { draft_id: JID }, as: :turbo_stream
    assert_response :success
    assert_select "#shared-dialog-title", text: "Delete journal?"
    t=token("#shared-content-dialog form")
    command=stub_request(:post, "#{api}/work/delete").with(body: { expected_version: 1, expected_draft_version: 1, draft_id: JID, contexts: contexts }).to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: { form_token: t, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s) }
    assert_redirected_to path
    assert_requested command
    view(d.merge(permissions: { prepare: false }))
    get path, params: { draft_id: JID }
    assert_select "#journal-header-actions button[disabled]", text: "Delete journal"
    get "#{path}/delete_dialog", params: { draft_id: JID }, as: :turbo_stream
    assert_response :not_found
  end
  test "journal details edit opens a shared dialog and preserves rejected values" do
    view
    get "#{path}/details_dialog", params: { draft_id: JID }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #shared-dialog-title", text: "Edit journal details"
    assert_select "[data-journal-details] input[name=name][value='Work journal']"
    t=token("[data-journal-details]")
    attrs={ expected_version: 1, expected_draft_version: 1, draft_id: JID, contexts: contexts, data: { name: "Renamed", posting_date: "2026-06-02", reference: "REF" } }
    command=stub_request(:post, "#{api}/work/details").with(body: attrs).to_return(status: 409, body: { error: "version_conflict" }.to_json)
    patch path, params: { form_token: t, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s), name: "Renamed", posting_date: "2026-06-02", reference: "REF" }
    assert_response :conflict
    assert_select "#shared-dialog-host [data-journal-details] input[name=name][value=Renamed]"
    assert_requested command
    t=token("#shared-dialog-host [data-journal-details]")
    command.to_return(status: 200, body: { draft_id: JID, stream_version: 2 }.to_json)
    patch path, params: { form_token: t, draft_id: JID, expected_version: "1", expected_draft_version: "1", contexts: contexts.transform_values(&:to_s), name: "Renamed", posting_date: "2026-06-02", reference: "REF" }
    assert_redirected_to "#{path}?draft_id=#{JID}"
    view(data.merge(permissions: { prepare: false }))
    get "#{path}/details_dialog", params: { draft_id: JID }, as: :turbo_stream
    assert_response :not_found
  end
  test "posting preview dialog reads the requested historical revision without editing" do
    d=data.merge(historical: true, permissions: { prepare: false })
    stub=stub_request(:get, api).with(query: { draft_id: JID, version: "1" }).to_return(status: 200, body: d.to_json)
    get "#{path}/posting_preview", params: { draft_id: JID, version: "1" }, as: :turbo_stream
    assert_response :success
    assert_select "#shared-dialog-title", text: "Saved posting preview · Unposted"
    assert_includes response.body, "Saved evidence for this revision"
    assert_select "#shared-content-dialog form", count: 0
    assert_requested stub
    assert_not_requested :post, "#{api}/reviews"
  end
  test "journal instructions live only in the shared user manual dialog" do
    view
    get path, params: { draft_id: JID }
    assert_select "#journal-header-actions a[data-turbo-stream]", text: "User manual"
    assert_not_includes response.body, "Type two or more characters"
    assert_not_includes response.body, "final posting follow in a later workflow"
    stub_request(:get, api).to_return(status: 200, body: data.merge(permissions: { prepare: false }).to_json)
    get "#{path}/user_manual", headers: { "Accept"=>"text/vnd.turbo-stream.html", "Accept-Language"=>"da-DK" }
    assert_response :success
    assert_select "turbo-stream[target=shared-dialog-host] #shared-dialog-title", text: "User manual"
    assert_select "#journal-user-manual p", count: 2
    assert_includes response.body, "Type two or more characters"
    assert_includes response.body, "Amounts use , as the decimal point"
    assert_includes response.body, "final posting follow in a later workflow"
    assert_select "#shared-content-dialog form", count: 0
    assert_not_requested :post, "#{api}/work/row"
  end
end
