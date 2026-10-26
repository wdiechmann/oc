require "test_helper"
require "stringio"

class SafeRescueLoggingTest < ActiveSupport::TestCase
  test "the Rails rescue subscriber does not emit exception messages or full paths" do
    buffer = StringIO.new
    original = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(buffer)
    error = RuntimeError.new("private-user-message@example.test secret-token")
    error.set_backtrace([ "/private/human-name/request.rb:123" ])
    ActiveSupport::Notifications.instrument("rescue_from_callback.action_controller", exception: error)
    assert_includes buffer.string, "RuntimeError"
    assert_not_includes buffer.string, "private-user-message"
    assert_not_includes buffer.string, "secret-token"
    assert_not_includes buffer.string, "human-name"
  ensure
    ActionController::Base.logger = original
  end
end
