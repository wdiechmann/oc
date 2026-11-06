class Components::Toast < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :vera_toast
  def initialize(message:, kind: "notice", check_url: nil, retry_url: nil)
    @message, @kind, @check, @retry = message, kind, check_url, retry_url
  end
  def view_template
    vera_toast(data: { kind: @kind }, class: "vera-toast") do
      button(type: "button", aria_label: "Dismiss notification", data: { toast_close: true }, class: "vera-toast-close") { "×" }
      p(role: @kind == "alert" ? "alert" : "status", class: "text-sm leading-relaxed") do
        if @message.is_a?(Hash)
          plain @message["message"] || @message[:message]
          if Rails.env.development? && (url = @message["sign_in_url"] || @message[:sign_in_url])
            plain " · "
            a(href: url, class: "font-semibold underline", data: { turbo: false }) { "Sign in to VERA" }
          end
        else
          plain @message
        end
      end
      a(href: @check, data: { turbo_stream: true }, class: "mt-3 inline-block text-sm font-semibold underline") { "Check completion" } if @check
      form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: Views::Base::BUTTON) } if @retry
    end
  end
end
