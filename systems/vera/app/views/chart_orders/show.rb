class Views::ChartOrders::Show < Views::Base
  register_element :chart_order_editor
  def initialize(data:, token: nil, message: nil, **options)
    super(**options)
    @data, @token, @message = data, token, message
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
  end
  def view_template
    a(href: tenant_book_chart_path(@tid, @bid), class: "text-sm text-teal-900 underline") { "← Chart of accounts" }
    p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
    h1(class: "mt-2 text-3xl font-semibold") { @data["review_id"] ? "Review chart order" : "Reorder chart" }
    p(class: "mt-4 text-sm text-stone-600") { "The complete current chart, including inactive rows. Only positions change: account numbers, IDs, fields and formula references stay the same. Positions are reassigned as 100, 200, 300… before atomic acceptance." }
    render Components::Toast.new(message: @message, kind: "alert") if @message
    @data["review_id"] ? review : editor
  end
  def editor
    rows = @data.fetch("rows")
    p(class: "mt-3 text-sm text-stone-500") { "#{rows.length} accounts · Revision #{@data['source_version']}" }
    return p(class: "mt-6") { "There are no current accounts to reorder." } if rows.empty?
    chart_order_editor(class: "mt-6 block") do
      p(class: "text-sm text-stone-600", id: "order-help") { "Select rows to move a block; otherwise move the focused row. ↑/↓, Home/End and PgUp/PgDn navigate. Space selects. Alt+↑/↓ moves; Alt+Home/End moves to first/last. Shift-click selects a range. Nothing is saved until review and acceptance." }
      form_with(url: preview_tenant_book_chart_order_path(@tid, @bid), data: { turbo: false, order_form: true }) do |f|
        f.hidden_field(:expected_version, value: @data.fetch("source_version"))
        div(class: "mt-4 flex flex-wrap items-center gap-2") do
          %w[up down first last].each do |action|
            button(type: "button", data: { order_move: action }, class: "rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm font-medium text-teal-900") { "Move #{action}" }
          end
          button(type: "button", data: { order_clear: true }, class: "px-3 py-2 text-sm text-teal-900 underline") { "Clear selection" }
        end
        div(class: "mt-3 flex flex-wrap items-end gap-3") do
          div(class: "min-w-0 grow") do
            label(for: "order-target", class: "text-sm font-medium") { "Insert selection before" }
            select(id: "order-target", data: { order_target: true }, class: FIELD) do
              option(value: "") { "Choose an account" }
              rows.each { |row| option(value: row.fetch("id")) { "#{row['number']} #{row['name']}" } }
            end
          end
          button(type: "button", data: { order_move: "before" }, class: "rounded-lg border border-stone-300 bg-white px-4 py-3 text-sm font-medium text-teal-900") { "Move before" }
        end
        p(id: "order-status", role: "status", aria_live: "polite", class: "my-4 text-sm font-medium text-teal-900") { "Accepted order shown. Select or focus a row to begin." }
        ol(data: { order_list: true }, class: "max-h-[60vh] overflow-y-auto rounded-xl border border-stone-200 bg-white", aria_describedby: "order-help") do
          rows.each_with_index do |row, index|
            li(data: { order_row: true, account_id: row.fetch("id"), original_position: row.fetch("position") }, tabindex: index.zero? ? "0" : "-1", class: "order-row flex items-center gap-3 border-b border-stone-100 px-3 py-3 text-sm focus:outline-2 focus:outline-teal-800") do
              input(type: "hidden", name: "ordered_ids[]", value: row.fetch("id"))
              input(type: "checkbox", data: { order_select: true }, aria_label: "Select #{row['number']} #{row['name']}", class: "h-4 w-4 shrink-0 accent-teal-900")
              span(data: { order_rank: true }, class: "w-7 shrink-0 text-xs text-stone-400") { (index + 1).to_s }
              div(class: "min-w-0 grow") do
                p(class: "break-words font-medium") { "#{row['number']} #{row['name']}" }
                p(class: "text-xs text-stone-500") { "#{row['kind']}#{row['active'] == false ? ' · Inactive' : ''}" }
              end
              span(data: { order_position: true }, class: "shrink-0 text-xs tabular-nums text-stone-500") { row.fetch("position").to_s }
            end
          end
        end
        div(class: "mt-1 flex flex-wrap items-center gap-4") do
          f.submit("Review order", class: BUTTON)
          f.submit("Review position rebalance", class: "mt-5 cursor-pointer rounded-lg border border-teal-900 bg-white px-5 py-3 text-sm font-semibold text-teal-900")
          a(href: tenant_book_chart_order_path(@tid, @bid), data: { order_discard: true }, class: "mt-5 text-sm text-teal-900 underline") { "Discard draft order" }
        end
      end
    end
  end
  def review
    plan = @data.fetch("plan")
    minutes = [ ((Time.iso8601(@data.fetch("expires_at")) - Time.current) / 60).ceil, 0 ].max
    p(class: "mt-4 text-sm") { "#{plan['changed_count']} positions change · #{plan['row_count']} accounts · Reviewed revision #{@data['expected_version']} · Expires in #{minutes} min" }
    div(class: "mt-6 max-h-[60vh] overflow-auto rounded-xl border border-stone-200 bg-white") do
      table(class: "w-full text-left text-sm") do
        thead(class: "bg-stone-100") { tr { %w[Account Type Before After].each { |label| th(class: "p-3") { label } } } }
        tbody do
          plan.fetch("rows").each do |row|
            tr(class: row["changed"] ? "border-t bg-teal-50" : "border-t") do
              td(class: "p-3") { "#{row['number']} #{row['name']}" }
              td(class: "p-3") { row["kind"] }
              td(class: "p-3 tabular-nums") { row.fetch("before_position").to_s }
              td(class: "p-3 tabular-nums") { row.fetch("after_position").to_s }
            end
          end
        end
      end
    end
    if @token
      form_with(url: tenant_book_chart_order_path(@tid, @bid), method: :patch, data: { turbo: false }) do |f|
        f.hidden_field(:form_token, value: @token)
        f.submit("Accept reviewed order", class: BUTTON)
      end
    else
      p(class: "mt-5 text-sm") { "This order review has already been accepted." }
    end
    a(href: tenant_book_chart_order_path(@tid, @bid), class: "mt-5 block text-sm text-teal-900 underline") { "Start again from current chart" }
  end
end
