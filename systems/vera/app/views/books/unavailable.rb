class Views::Books::Unavailable < Views::Base
  def initialize(message:, check_url: nil, retry_url: nil, **options)
    super(**options)
    @message, @check, @retry = message, check_url, retry_url
  end
  def view_template
    div(id: "vera-book-content") do
      h1(class: "text-3xl font-semibold") { "Book setup" }
      p(role: "alert", class: "mt-5 rounded-xl border border-amber-200 bg-amber-50 p-5") { @message }
      a(href: @check, class: "mt-5 inline-block font-medium text-teal-900 hover:underline") { "Check completion" } if @check
      form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      a(href: root_path, class: "mt-5 block text-sm font-medium text-teal-900 hover:underline") { "Return to your workspaces" }
    end
  end
end
