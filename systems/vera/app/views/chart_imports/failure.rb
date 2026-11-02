class Views::ChartImports::Failure < Views::Base
  def initialize(message:, chart_url:, review_url: nil, **options)
    super(**options)
    @message, @chart, @review = message, chart_url, review_url
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Chart CSV review" }
    p(role: "alert", class: "mt-5 rounded-lg bg-amber-50 p-4") { @message }
    a(href: @review, class: "mt-5 block text-teal-900 underline") { "Return to CSV review and column mapping" } if @review
    a(href: @chart, class: "mt-5 block text-teal-900 underline") { "Return to chart of accounts" }
  end
end
