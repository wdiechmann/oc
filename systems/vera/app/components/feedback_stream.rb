class Components::FeedbackStream < Components::Base
  register_element :turbo_stream
  def initialize(message:)
    @message = message
  end
  def view_template
    turbo_stream(action: "update", target: "vera-feedback") do
      template { p(role: "alert", class: "mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4") { @message } }
    end
  end
end
