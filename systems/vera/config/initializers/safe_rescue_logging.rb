require "action_controller/log_subscriber"
module SafeRescueLogging
  def rescue_from_callback(event)
    info { { code: "request.rescued", exception_class: event.payload[:exception].class.name }.to_json }
  end
end
ActionController::LogSubscriber.prepend(SafeRescueLogging)
