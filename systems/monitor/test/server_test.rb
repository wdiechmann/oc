require "minitest/autorun"
require "net/http"
require "json"
require_relative "../lib/ep_monitor/server"

class ServerTest < Minitest::Test
  def test_health_distinguishes_live_from_not_ready_and_recovers
    agent = Object.new
    agent.define_singleton_method(:statistics) { { ready: false, queue: { pending: 1, quarantined: 0 } } }
    server = EpMonitor::Server.new(agent, port: 0)
    server.run
    get = ->(path) { Net::HTTP.new("127.0.0.1", server.port, nil).get(path) }
    assert_equal "200", get.call("/health/live").code
    assert_equal "503", get.call("/health/ready").code
    assert_includes get.call("/metrics").body, "monitor_queue_pending 1"
    agent.define_singleton_method(:statistics) { { ready: true, queue: { pending: 0, quarantined: 0 } } }
    assert_equal "200", get.call("/health/ready").code
    assert_equal "no-store", get.call("/status")["Cache-Control"]
    agent.define_singleton_method(:statistics) { raise IOError }
    assert_equal "200", get.call("/health/live").code
    assert_equal "503", get.call("/health/ready").code
  ensure
    server&.stop
  end
end
