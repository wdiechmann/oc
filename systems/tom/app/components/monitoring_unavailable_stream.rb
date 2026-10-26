class Components::MonitoringUnavailableStream < Components::Base
  def initialize(message:, reference:)
    @message, @reference = message, reference
  end
  def view_template
    render Components::FeedbackStream.new(message: @message, reference: @reference, operation_id: Monitoring::Current.operation_id)
    %w[monitoring-list monitoring-detail].each do |target|
      render Components::UpdateStream.new(target: target, operation_id: Monitoring::Current.operation_id, component: Components::Feedback.new(message: @message))
    end
  end
end
