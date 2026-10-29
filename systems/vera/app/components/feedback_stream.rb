class Components::FeedbackStream < Components::Base
  register_element :turbo_stream
  def initialize(message:, check_url: nil)
    @message, @check = message, check_url
  end
  def view_template
    turbo_stream(action: "update", target: "vera-feedback") do
      template do
        a(href: @check, data: { turbo_stream: true }, class: "mb-4 inline-block font-medium text-teal-900 hover:underline") { "Check completion" } if @check
        p(role: "alert", class: "mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4") { @message }
      end
    end
  end
end
