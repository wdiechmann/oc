require "time"
require_relative "spool"
require_relative "client"

module EpMonitor
  class Agent
    attr_reader :last_tick
    def initialize(spool:, client:, probes: [], probe: ->(url) { Client.probe(url) }, clock: -> { Time.now.to_i }, notifier: nil)
      @spool, @client, @probes, @probe, @clock = spool, client, probes, probe, clock
      @notifier = notifier || method(:local_notice)
      @state = {}
      @next_drain, @backoff = 0, 1
      @last_tick, @last_delivery = 0, nil
      @probe_file = File.join(spool.directory,".probe-state")
      @state = JSON.parse(File.read(@probe_file)) if File.file?(@probe_file)
      probes.each_with_index do |p, index|
        prefix = "Probe #{index + 1}"
        raise ArgumentError, "#{prefix}: expected a configuration object" unless p.is_a?(Hash)
        raise ArgumentError, "#{prefix}: name must use 1–80 letters, digits, dots, underscores or hyphens" unless p["name"].to_s.match?(/\A[A-Za-z0-9_.-]{1,80}\z/)
        raise ArgumentError, "#{prefix}: source_id must be a registered reporting source UUID; replace the example placeholder" unless p["source_id"].to_s.match?(Spool::UUID)
        raise ArgumentError, "#{prefix}: failures must be an integer from 1 to 10" unless p["failures"].is_a?(Integer) && p["failures"].between?(1,10)
        raise ArgumentError, "#{prefix}: recoveries must be an integer from 1 to 10" unless p.fetch("recoveries",3).is_a?(Integer) && p.fetch("recoveries",3).between?(1,10)
      end
    end

    def tick
      @probes.each do |p|
        old = @state.fetch(p["name"], { "failures"=>0,"successes"=>0,"open"=>false })
        healthy = @probe.call(p.fetch("url"))
        current = old.merge("healthy"=>healthy,"checked_at"=>@clock.call,
          "failures"=>healthy ? 0 : old.fetch("failures",0)+1,"successes"=>healthy ? old.fetch("successes",0)+1 : 0)
        breached = !healthy && current["failures"] >= p["failures"] && (!old["open"] || @clock.call-old.fetch("last_notice",0) >= 300)
        recovered = healthy && old["open"] && current["successes"] >= p.fetch("recoveries",3)
        if breached || recovered
          current["open"] = !recovered
          current["reference"] = SecureRandom.uuid if !old["open"]
          current["last_notice"] = @clock.call
          code = recovered ? "condition.recovered" : "dependency.unavailable"
          observation = { source_id: p.fetch("source_id"), source_observation_id: SecureRandom.uuid,
            correlation_id: current.fetch("reference"), observed_at: Time.at(@clock.call).utc.iso8601(6),code: code,component: p.fetch("name") }
          @spool.enqueue(observation)
          @notifier.call({ code: code, probe: p.fetch("name"), correlation_id: current.fetch("reference"), recorded_at: @clock.call })
        end
        @state = @state.merge(p.fetch("name")=>current)
      end
      persist_state
      drain if @clock.call >= @next_drain
      @last_tick = @clock.call
      statistics
    end

    def drain
      10.times do
        record = @spool.claim
        break unless record
        begin
          body = record.fetch(:body)
          observation = body.fetch("observation")
          if body["kind"] == "alert_outcome"
            id = observation.fetch("alert_id")
            raise ArgumentError unless id.match?(Spool::UUID)
            status = @client.post("/monitoring/alerts/#{id}/outcome", observation.slice("attempt_id","status"))
          else
            status = @client.post(body["delivery"] ? "/monitoring/delivery-outcomes" : "/monitoring/observations", observation)
          end
          if status.between?(200,299)
            @spool.acknowledge(record)
            @backoff = 1; @last_delivery = @clock.call
          elsif [400,401,403,404,409,422].include?(status)
            @spool.quarantine(record)
          else
            @spool.retry_later(record)
            pause_drain
            break
          end
        rescue StandardError
          @spool.retry_later(record)
          pause_drain
          break
        end
      end
    end

    def statistics
      queue = @spool.statistics
      delivered = (queue[:pending] + queue[:inflight]) == 0 || (@last_delivery && @clock.call-@last_delivery < 60)
      { alive: true, ready: !!(@last_tick > 0 && @clock.call-@last_tick < 45 && delivered && queue[:quarantined] == 0 && @state.values.all? { |p| p["healthy"] && !p["open"] }),
        probes: @state, queue: queue, last_tick: @last_tick, last_delivery: @last_delivery }
    end
    private
    def pause_drain
      @next_drain = @clock.call + @backoff
      @backoff = [@backoff*2,300].min
    end
    def persist_state
      path = @probe_file+".tmp"
      File.open(path,File::WRONLY|File::CREAT|File::TRUNC,0o600) { |f| f.write(JSON.generate(@state)); f.flush; f.fsync }
      File.rename(path,@probe_file)
    end
    def local_notice(notice)
      path = File.join(@spool.directory,".notices")
      if File.file?(path) && File.size(path) > 65_536
        File.unlink(path+".2") if File.file?(path+".2")
        File.rename(path+".1",path+".2") if File.file?(path+".1")
        File.rename(path,path+".1")
      end
      File.open(path,File::WRONLY|File::CREAT|File::APPEND,0o600) { |f| f.puts(JSON.generate(notice)); f.flush; f.fsync }
      $stderr.puts(JSON.generate(notice))
    end
  end
end
