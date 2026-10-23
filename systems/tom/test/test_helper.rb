ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1)

    # Add more helper methods to be used by all tests here...
  end
end

require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: false)

class ActiveSupport::TestCase
  setup { Mail::TestMailer.deliveries.clear }
end
