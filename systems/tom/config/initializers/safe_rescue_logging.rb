require "action_controller/log_subscriber"

# Rails 8.1's default subscriber logs exception.message before rescue_from runs.
# Keep the notification and other controller logs; replace only that unsafe output.
module SafeRescueLogging
  def rescue_from_callback(event)
    info do
      { code: "request.rescued", exception_class: event.payload[:exception].class.name,
        correlation_id: Monitoring::Current.correlation_id }.to_json
    end
  end
end

ActionController::LogSubscriber.prepend(SafeRescueLogging)
