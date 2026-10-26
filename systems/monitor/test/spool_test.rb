require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ep_monitor/spool"

class SpoolTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("monitor-test")
    @now = Time.now.to_i
    @key = Base64.strict_encode64("x" * 32)
    @observation = { source_observation_id: SecureRandom.uuid, source_id: SecureRandom.uuid, code: "application.exception", correlation_id: SecureRandom.uuid }
  end
  def teardown = FileUtils.remove_entry(@dir)
  def spool(**options) = EpMonitor::Spool.new(directory: @dir, key: @key, clock: -> { @now }, **options)

  def test_restart_preserves_authenticated_ciphertext_and_stable_replay
    assert spool.enqueue(@observation)
    refute File.read(Dir.glob("#{@dir}/*.pending").first).include?("application.exception")
    assert spool.enqueue(@observation)
    assert_equal 1, spool.statistics[:pending]
    record = spool.claim
    assert_equal @observation[:source_observation_id], record[:body]["observation"]["source_observation_id"]
    @now += 61
    recovered = spool.claim
    assert_equal record[:body], recovered[:body]
    spool.acknowledge(recovered)
    assert_equal 0, spool.statistics[:pending]
  end

  def test_quota_expiry_and_changed_content_are_explicit
    assert spool(max_files: 1, max_age: 60).enqueue(@observation)
    refute spool(max_files: 1, max_age: 60).enqueue(@observation.merge(source_observation_id: SecureRandom.uuid))
    assert_equal 1, spool.statistics[:losses]["full"]
    assert_raises(EpMonitor::Spool::Invalid) { spool.enqueue(@observation.merge(code: "request.conflict")) }
    @now += 61
    assert_equal 0, spool(max_age: 60).statistics[:pending]
    assert_equal 1, spool.statistics[:losses]["expired"]
  end

  def test_tamper_is_quarantined_instead_of_silently_dropped
    spool.enqueue(@observation)
    path = Dir.glob("#{@dir}/*.pending").first
    data = JSON.parse(File.read(path)); data["tag"] = Base64.strict_encode64("z" * 16)
    File.write(path, JSON.generate(data))
    assert_nil spool.claim
    assert_equal 1, spool.statistics[:quarantined]
    assert_equal 1, spool.statistics[:losses]["unreadable"]
  end
end
