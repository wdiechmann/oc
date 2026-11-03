require "test_helper"
require "stringio"

class ChartImportsTest < ActionDispatch::IntegrationTest
  EP = "http://localhost:4000/api/v1"
  TID = "657df2d1-0f99-4007-a914-e26de1d58dc9"
  BID = "df763842-2538-4ccb-8445-17e232c37d84"
  IID = "bd763842-2538-4ccb-8445-17e232c37d84"
  setup do
    Rails.application.config.x.ep_backend_token = "v"*48
    stub_request(:post, "#{EP}/auth/magic-links/verify").to_return(status: 200, body: { token: "test-session", expires_at: 1.hour.from_now.iso8601 }.to_json)
    get "/session/verify", params: { token: "a"*43 }
    post "/session"
  end
  teardown { Rails.application.config.x.ep_backend_token = nil }
  def path = "/tenants/#{TID}/books/#{BID}/chart_import"
  def api = "#{EP}/tenants/#{TID}/finance/books/#{BID}"
  def review
    { tenant_id: TID, book_id: BID, import_id: IID, mode: "merge", row_count: 1, expires_at: 1.hour.from_now.iso8601, columns: %w[type number name position], headers: %w[kind code label order], sample: [ [ "posting", "0010", "Bank", "100" ] ], mapping: { type: "kind", number: "code", name: "label", position: "order" }, expected_version: 2, digest: "review-digest", plan: { mode: "merge", valid: true, errors: [], counts: { create: 1 }, rows: [ { line: 2, operation: "create", before: nil, after: { kind: "posting", number: "0010", name: "Bank", position: 100 }, errors: [] } ] } }
  end
  def ready_review
    stub_request(:get, "#{api}/chart-imports/#{IID}").to_return(status: 200, body: review.to_json)
    get path, params: { import_id: IID }
    assert_response :success
    css_select("input[name=form_token]").first["value"]
  end

  test "codec preserves strings, Unicode, quotes, multiline text and safely escaped formula-like cells" do
    rows = [ [ "0010", "Æble, \"bank\"\nnext", "=1+2", " -2", "@SUM(1)", "'literal", "'[0010]", "[0010] * 2" ] ]
    columns = %w[number name danger negative at apostrophe quoted formula]
    csv = ChartCsv.generate(columns, rows)
    assert_includes csv, "'=1+2"
    assert_equal rows, ChartCsv.parse(StringIO.new("\uFEFF" + csv)).fetch(:records)
    assert_equal columns, ChartCsv.parse(StringIO.new(csv)).fetch(:headers)
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("a,a\n1,2")) }
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("a,b\n1")) }
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("a\n" + "x\n" * 501)) }
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("x" * (ChartCsv::MAX_BYTES + 1))) }
  end

  test "upload and mapping forward bounded strings without accepting accounts" do
    upload = stub_request(:post, "#{api}/chart-imports").with(body: { create_codes: false, mode: "replace", headers: %w[kind code label order], records: [ [ "posting", "0010", "Bank", "100" ] ] }).to_return(status: 200, body: review.to_json)
    file = Rack::Test::UploadedFile.new(StringIO.new("kind,code,label,order\nposting,0010,Bank,100\n"), "text/csv", original_filename: "chart.csv")
    post "#{path}/upload", params: { csv: file }
    assert_redirected_to "#{path}?import_id=#{IID}"
    assert_requested upload
    mapping = stub_request(:post, "#{api}/chart-imports/#{IID}/preview").with(body: { mapping: review[:mapping], create_codes: false, mode: "replace" }).to_return(status: 200, body: review.to_json)
    post "#{path}/preview", params: { import_id: IID, mapping: review[:mapping].merge(formula: "") }
    assert_response :success
    assert_select "input[value='Accept reviewed changes']"
    assert_select "select[name='mapping[type]'] option[value=kind][selected]"
    assert_requested mapping
    assert_not_requested :post, "#{api}/chart-imports/#{IID}/accept"
  end

  test "acceptance is bound to the signed review rather than hidden replacement parameters" do
    token = ready_review
    accept = stub_request(:post, "#{api}/chart-imports/#{IID}/accept").with(body: { digest: "review-digest", expected_version: 2 }, headers: { "Idempotency-Key"=>/\A[0-9a-f-]{36}\z/ }).to_return(status: 200, body: { stream_version: 3 }.to_json)
    patch path, params: { form_token: token, digest: "tampered", expected_version: 99, import_id: BID }
    assert_redirected_to "/tenants/#{TID}/books/#{BID}/chart"
    assert_requested accept
    patch path, params: { form_token: "tampered" }
    assert_response :unprocessable_entity
    assert_requested accept, times: 1
  end

  test "unknown acceptance checks the receipt then retries only the original small pointer" do
    token = ready_review
    key = Rails.application.message_verifier(:finance_setup).verified(token, purpose: :finance_setup).fetch("key")
    accept = stub_request(:post, "#{api}/chart-imports/#{IID}/accept").with(body: { digest: "review-digest", expected_version: 2 }, headers: { "Idempotency-Key"=>key }).to_timeout
    patch path, params: { form_token: token }
    assert_response :service_unavailable
    assert_select "a[href='#{path}/completion']"
    post "#{path}/upload", params: {}
    assert_response :success
    assert_requested accept, times: 1
    stub_request(:get, "#{EP}/me/commands").with(query: { command_type: "FinanceChartImport:accept", idempotency_key: key }).to_return(status: 200, body: { status: "unknown" }.to_json)
    get "#{path}/completion"
    assert_select "form[action='#{path}/retry']"
    accept.to_return(status: 200, body: { stream_version: 3 }.to_json)
    post "#{path}/retry", params: { digest: "replacement" }
    assert_redirected_to "/tenants/#{TID}/books/#{BID}/chart"
    assert_requested accept, times: 2
  end

  test "exports cover the requested snapshot and templates include a scoped demo row" do
    stub_request(:get, "#{api}/chart-export").with(query: { q: "Bank", source_version: "2" }).to_return(status: 200, body: { columns: %w[number name], rows: [ [ "0010", "=Bank" ] ], source_version: 2 }.to_json)
    get "#{path}/export", params: { q: "Bank", source_version: "2" }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.headers["Content-Disposition"], "r2.csv"
    assert_equal [ [ "number", "name" ], [ "0010", "'=Bank" ] ], CSV.parse(response.body)
    stub_request(:get, "#{api}/chart-imports").to_return(status: 200, body: { columns: %w[tenant_id book_id type name position active] }.to_json)
    get "#{path}/template"
    assert_equal [ %w[tenant_id book_id type name position active], [ TID, BID, "header", "demo", "100", "true" ] ], CSV.parse(response.body)
  end

  test "row and chart errors suppress acceptance and protected errors clear the review" do
    invalid = review.deep_dup
    invalid[:plan].merge!(valid: false, errors: [ "invalid_formula_cycle_or_reference" ])
    invalid[:plan][:rows][0].merge!(operation: "error", errors: [ "position_taken" ])
    stub_request(:get, "#{api}/chart-imports/#{IID}").to_return(status: 200, body: invalid.to_json)
    get path, params: { import_id: IID }
    assert_includes response.body, "position_taken"
    assert_includes response.body, "invalid_formula_cycle_or_reference"
    assert_select "input[value='Accept reviewed changes']", count: 0
    stub_request(:get, "#{api}/chart-imports/#{IID}").to_return(status: 404, body: { error: "not_found" }.to_json)
    get path, params: { import_id: IID }
    assert_response :not_found
    assert_not_includes response.body, "Bank"
  end
  test "code creation selection is explicit, retained and shown before acceptance" do
    data = review.deep_dup
    data[:create_codes] = true
    data[:plan][:rows][0][:inferred_type] = "posting"
    data[:plan][:catalogue_creates] = [ { kind: "vat", code: "V25", name: "V25" } ]
    stub_request(:get, "#{api}/chart-imports/#{IID}").to_return(status: 200, body: data.to_json)
    get path, params: { import_id: IID }
    assert_select "input[type=checkbox][name=create_codes][checked]"
    assert_select "label", text: "create type, vat- and category-codes"
    assert_includes response.body, "Create VAT code: V25"
    assert_includes response.body, "Guessed type: posting"
    assert_includes response.body, "Types: header, posting, calculation."
    preview = stub_request(:post, "#{api}/chart-imports/#{IID}/preview").with(body: { mapping: review[:mapping], create_codes: true, mode: "replace" }).to_return(status: 200, body: data.to_json)
    post "#{path}/preview", params: { import_id: IID, mapping: review[:mapping], create_codes: "1" }
    assert_response :success
    assert_requested preview
  end
  test "regional spreadsheet exports skip empty rows and preserve semicolon-delimited strings" do
    csv = ";;;;\r\nnumber;name;position;active;type\r\n0010;\"Salg, varer; øvrige\";10;;\r\n;;;;\r\n"
    parsed = ChartCsv.parse(StringIO.new(csv))
    assert_equal %w[number name position active type], parsed[:headers]
    assert_equal [ [ "0010", "Salg, varer; øvrige", "10", "", "" ] ], parsed[:records]
    assert_equal [ [ "0010", "Bank" ] ], ChartCsv.parse(StringIO.new("number\tname\n0010\tBank\n"))[:records]
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("name;name\na;b\n")) }
    assert_raises(ChartCsv::Invalid) { ChartCsv.parse(StringIO.new("number;name\n0010;Bank;extra\n")) }
  end
  test "replacement is the default and review explicitly lists retained and retiring accounts" do
    ready = { tenant_id: TID, book_id: BID, status: "ready", permissions: { configure: true }, catalogues_initialized: true }
    stub_request(:get, "#{api}/chart-imports").to_return(status: 200, body: ready.to_json)
    get path
    assert_select "select[name=mode] option[value=replace][selected]"
    assert_select "option[value=merge]", text: "Merge into existing chart"
    data = review.deep_dup
    data[:mode] = "replace"
    data[:plan].merge!(mode: "replace", retained_count: 1, retirements: [ { operation: "retire", before: { name: "Old account", position: 100 }, after: { name: "Old account", position: 100, active: false, retired: true }, errors: [] } ])
    stub_request(:get, "#{api}/chart-imports/#{IID}").to_return(status: 200, body: data.to_json)
    get path, params: { import_id: IID }
    assert_select "input[value='Accept chart replacement']"
    assert_includes response.body, "1 existing accounts retained; 1 accounts will be retired"
    assert_includes response.body, "Existing account: retire"
    token = css_select("input[name=form_token]").first["value"]
    accept = stub_request(:post, "#{api}/chart-imports/#{IID}/accept").with(body: { digest: "review-digest", expected_version: 2 }).to_return(status: 200, body: { stream_version: 4 }.to_json)
    patch path, params: { form_token: token, mode: "merge" }
    assert_response :see_other
    assert_requested accept
  end
end
