class Components::BooksUnavailableStream < Components::Base
  register_element :turbo_stream
  def initialize(message:, check_url: nil)
    @message, @check = message, check_url
  end
  def view_template
    turbo_stream(action: "update", target: "vera-book-content") do
      template do
        p(role: "alert", class: "rounded-xl border border-amber-200 bg-amber-50 p-5") { @message }
        a(href: @check, data: { turbo_stream: true }, class: "mt-5 inline-block text-sm font-medium text-teal-900 hover:underline") { "Check completion" } if @check
        a(href: root_path, class: "mt-5 inline-block text-sm font-medium text-teal-900 hover:underline") { "Return to your workspaces" }
      end
    end
  end
end
