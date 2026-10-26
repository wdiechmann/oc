class Views::Monitoring::Status < Views::Base
  def initialize(message:, reference:, **options)
    super(**options)
    @message, @reference = message, reference
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Request status" }
    render Components::Feedback.new(message: @message, reference: @reference)
  end
end
