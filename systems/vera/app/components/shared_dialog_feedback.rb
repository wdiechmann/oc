class Components::SharedDialogFeedback < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(message:, check_url: nil, retry_url: nil)
    @message, @check, @retry = message, check_url, retry_url
  end
  def view_template
    h2(id: "shared-dialog-title", class: "mt-6 text-xl font-semibold") { "Enclosure save status" }
    p(role: "alert", class: "mt-3 text-sm text-amber-900") { @message }
    a(href: @check, data: { turbo_stream: true }, class: "mt-4 block underline") { "Check completion" } if @check
    form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: Views::Base::BUTTON) } if @retry
  end
end
