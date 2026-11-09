class Components::BookOverview < Components::Base
  include Phlex::Rails::Helpers::NumberWithPrecision
  def initialize(data:, tenant_id:, book_id:)
    @data, @tid, @bid = data, tenant_id, book_id
  end
  def view_template
    return unless @data
    unless @data["status"] == "ready"
      p(role: "status", class: "mt-6 rounded-xl border border-stone-200 bg-white p-5 text-sm text-stone-600") { @data["status"] == "external" ? "The financial overview is provided by this book’s external accounting authority." : "The financial overview is updating or unavailable. Refresh when the chart view is ready." }
      return
    end
    start = Date.iso8601(@data.fetch("start_date"))
    year = start.month == 1 ? start.year.to_s : "#{start.year}–#{start.year + 1}"
    section(class: "mt-6 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6", aria: { label: "Financial overview" }) do
      div(class: "flex items-center justify-between gap-4") do
        h2(class: "text-xl font-semibold text-slate-700") do
          plain "Overview #{year} "
          span(title: "Posted journals through #{@data['as_of']}. Current income/expense category mappings apply to both years. Percentage changes compare the same fiscal YTD last year; no percentage is shown when its value was zero or negative.", aria_label: "About this overview", tabindex: "0", class: "cursor-help text-sm text-stone-400") { "ⓘ" }
        end
        p(class: "text-xs text-slate-600") { "All amounts in #{@data['currency']}" }
      end
      div(class: "mt-4 grid grid-cols-1 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-stone-50 sm:grid-cols-3 sm:divide-x sm:divide-y-0 sm:py-4") do
        [ [ "Income", "income_minor", "text-teal-500" ], [ "Expenses", "expenses_minor", "text-red-500" ], [ "Profit / loss", "profit_minor", "text-slate-700" ] ].each do |label, key, color|
          div(class: "min-w-0 px-4 py-3 text-center sm:py-0") do
            p(class: "text-xs font-semibold text-slate-600") { label }
            p(class: "mt-1 text-xl font-bold tabular-nums sm:text-2xl #{color}", data: { overview_total: key }) { money(@data.fetch("totals").fetch(key)) }
            change = @data.fetch("change_bps")[key]
            if change
              favorable = key == "expenses_minor" ? change <= 0 : change >= 0
              p(title: "Compared with fiscal YTD through #{@data['prior_as_of']}", class: "mt-1 text-xs font-semibold #{favorable ? 'text-teal-600' : 'text-red-500'}") { "#{change < 0 ? '↘' : '↗'} #{number_with_precision(BigDecimal(change.abs.to_s) / 100, precision: 1, strip_insignificant_zeros: true, separator: ',')} %" }
            else
              p(title: "No positive previous-period value to compare", class: "mt-1 text-xs text-stone-400") { "—" }
            end
          end
        end
      end
      p(class: "mt-3 text-xs text-stone-500") { "Fiscal YTD through #{@data['as_of']} · #{@data['journal_count']} posted journals" }
      p(class: "mt-3 text-sm text-stone-500") { "No posted journals in this fiscal year." } if @data["journal_count"].zero?
      div(class: "mt-4 flex justify-end gap-4 text-xs text-stone-600") do
        span { span(class: "mr-1 inline-block h-2 w-2 rounded-full bg-teal-500"); plain "Income" }
        span { span(class: "mr-1 inline-block h-2 w-2 rounded-full bg-red-500"); plain "Expenses" }
      end
      div(class: "overflow-x-auto") { chart }
      p(class: "mt-1 text-xs text-stone-400 sm:hidden") { "Swipe the chart to see all months." }
      details(class: "mt-3 text-sm text-stone-600") do
        summary(class: "cursor-pointer text-teal-900") { "Monthly figures" }
        div(class: "mt-2 overflow-x-auto") do
          table(class: "w-full whitespace-nowrap text-right text-xs tabular-nums") do
            thead { tr { %w[Month Income Expenses Result].each { |label| th(scope: "col", class: "p-2") { label } } } }
            tbody do
              @data.fetch("months").each do |month|
                tr(class: "border-t border-stone-200") do
                  th(scope: "row", class: "p-2 font-normal") { month["month"][0, 7] }
                  %w[income_minor expenses_minor].each { |key| td(class: "p-2") { month["future"] ? "—" : money(month[key]) } }
                  td(class: "p-2") { month["future"] ? "—" : money(month["income_minor"] - month["expenses_minor"]) }
                end
              end
            end
          end
        end
      end
      warnings = @data.fetch("classification_warnings", [])
      if warnings.any?
        details(class: "mt-3 text-sm text-amber-900") do
          summary(class: "cursor-pointer") { "#{warnings.length} unclassified accounts excluded — check categories" }
          warnings.each { |account| p(class: "mt-1") { "#{account['number']} · #{account['name']}" } }
        end
      end
    end
  end
  def money(minor) = number_with_precision(BigDecimal(minor.to_s) / 100, precision: 2, delimiter: ".", separator: ",")
  def nice(value)
    return 0 if value <= 0
    step = 10 ** [ value.to_s.length - 2, 0 ].max
    ((value + step - 1) / step) * step
  end
  def chart
    months = @data.fetch("months")
    values = months.flat_map { |month| [ month["income_minor"], month["expenses_minor"] ] }
    upper, lower = nice([ values.max || 0, 0 ].max), -nice([ -(values.min || 0), 0 ].max)
    upper = 100 if upper == lower
    y = ->(value) { 324.0 - (value - lower).to_f / (upper - lower) * 300 }
    baseline = y.call(0)
    svg(viewbox: "0 0 960 380", class: "block w-full min-w-[36rem]", role: "img", aria_labelledby: "book-overview-chart-title book-overview-chart-description") do |s|
      s.title(id: "book-overview-chart-title") { "Monthly income and expenses" }
      s.desc(id: "book-overview-chart-description") { "Posted income and expenses by fiscal month through #{@data['as_of']}. Green bars show income, red bars show expenses. Negative bars indicate reversals. Exact amounts are in Monthly figures below." }
      5.times do |index|
        amount = upper - (upper - lower) * index / 4
        s.text(x: 90, y: y.call(amount) + 4, fill: "#94a3b8", font_size: 13, text_anchor: "end") { number_with_precision(BigDecimal(amount.to_s) / 100, precision: amount.abs < 100 ? 2 : 0, delimiter: ".", separator: ",") }
      end
      s.line(x1: 100, y1: baseline, x2: 940, y2: baseline, stroke: "#e2e8f0")
      months.each_with_index do |month, index|
        x = 100 + index * 70
        date = Date.iso8601(month["month"])
        s.line(x1: x, y1: 24, x2: x, y2: 324, stroke: "#e2e8f0")
        [ [ "income_minor", "#00bfa5", 19, "Income" ], [ "expenses_minor", "#ff383e", 36, "Expenses" ] ].each do |key, color, offset, label|
          value = month[key]
          s.rect(x: x + offset, y: [ baseline, y.call(value) ].min, width: 14, height: (baseline - y.call(value)).abs, rx: 6, fill: color) do
            s.title { "#{date.strftime('%B %Y')} · #{label}: #{money(value)} #{@data['currency']}" }
          end
        end
        s.text(x: x + 35, y: 350, fill: month["future"] ? "#cbd5e1" : "#94a3b8", font_size: 13, text_anchor: "middle") { Date::ABBR_MONTHNAMES[date.month].downcase }
      end
    end
  end
end
