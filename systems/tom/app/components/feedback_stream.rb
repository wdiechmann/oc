class Components::FeedbackStream < Components::Base
  register_element :turbo_stream
  def initialize(**options)
    @options = options
  end

  def view_template
    turbo_stream(action: "update", target: "tom-feedback", data: { operation_id: @options[:operation_id] }) do
      template { render Components::Feedback.new(**@options) }
    end
  end
end
