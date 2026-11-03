class Views::ChartOrders::Failure < Views::Base
  def initialize(message:, order_url:, chart_url:, **options)
    super(**options)
    @message, @order, @chart = message, order_url, chart_url
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Chart order" }
    p(role: "alert", class: "mt-5 rounded-lg bg-amber-50 p-4") { @message }
    a(href: @order, class: "mt-5 block text-teal-900 underline") { "Open current chart order" }
    a(href: @chart, class: "mt-4 block text-teal-900 underline") { "Return to chart" }
  end
end
