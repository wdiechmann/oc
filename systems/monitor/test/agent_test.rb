require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ep_monitor/agent"
class AgentTest < Minitest::Test
  class FakeClient
    attr_accessor :status
    attr_reader :sent
    def initialize = (@status = 503; @sent = [])
    def post(path,body) = (@sent << [path,body]; @status)
  end
  def setup
    @dir = Dir.mktmpdir("monitor-agent")
    @now = Time.now.to_i
    @spool = EpMonitor::Spool.new(directory: @dir,key: Base64.strict_encode64("a"*32),clock: -> { @now })
    @client = FakeClient.new; @healthy = false; @notices = []
    probes = [{"name"=>"ep-readiness","url"=>"http://localhost:4000/health/ready","source_id"=>SecureRandom.uuid,"failures"=>3}]
    @agent = EpMonitor::Agent.new(spool: @spool,client: @client,probes: probes,clock: -> { @now },probe: ->(_) { @healthy },notifier: ->(n) { @notices << n })
  end
  def teardown = FileUtils.remove_entry(@dir)
  def tick = (@now += 15; @agent.tick)
  def test_independent_outage_recording_and_durable_recovery
    3.times { tick }
    assert_equal 1,@notices.length
    assert_equal "dependency.unavailable",@notices.first[:code]
    assert_equal 1,@spool.statistics[:pending]
    refute @agent.statistics[:ready]
    first_id = @client.sent.first.last["source_observation_id"]
    @client.status = 200; @healthy = true
    3.times { tick }
    assert @agent.statistics[:ready]
    assert_equal 0,@spool.statistics[:pending]
    assert_equal "condition.recovered",@notices.last[:code]
    assert_equal first_id,@client.sent[1].last["source_observation_id"]
  end
  def test_permanent_rejection_is_quarantined_and_never_spins
    @client.status = 401
    3.times { tick }
    assert_equal 1,@spool.statistics[:quarantined]
    count = @client.sent.length
    2.times { tick }
    assert_equal count,@client.sent.length
    refute @agent.statistics[:ready]
  end
  def test_inflight_backlog_is_not_reported_ready_before_lease_recovery
    @healthy = true
    @spool.enqueue({source_observation_id: SecureRandom.uuid, code: "application.exception"})
    @spool.claim
    3.times { tick }
    assert_equal 1, @spool.statistics[:inflight]
    refute @agent.statistics[:ready]
    @client.status = 200
    tick
    assert @agent.statistics[:ready]
  end

end
