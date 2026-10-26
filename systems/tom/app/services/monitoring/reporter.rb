module Monitoring
  class Reporter
    UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

    def self.sources
      configured = Rails.application.config.x.monitoring_sources
      return configured if configured.is_a?(Hash)
      return {} if Rails.env.test?
      json = ENV["TOM_MONITORING_SOURCES_JSON"].presence
      return discover_sources unless json

      value = JSON.parse(json)
      raise ArgumentError unless value.is_a?(Hash) && value.all? { |k, v| k.match?(/\A(?:global|tenant:[0-9a-f-]{36}(?::occasion:[0-9a-f-]{36})?)\z/) && v.is_a?(String) && v.match?(UUID) }
      value
    rescue JSON::ParserError, ArgumentError
      Rails.logger.warn({ code: "monitoring.configuration_invalid" }.to_json)
      {}
    end

    def self.discover_sources
      @discovery_mutex ||= Mutex.new
      @discovery_mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return @bindings if @bindings && now-(@bindings_at || 0) < 60
        begin
          value = Ep::Client.new(instrument: false, timeout: 0.5).monitoring_bindings.fetch("sources")
          raise ArgumentError unless value.is_a?(Hash) && value.values.all? { |v| v.is_a?(String) && v.match?(UUID) }
          @bindings = value
          @bindings_at = now
        rescue StandardError
          @bindings ||= {}
          @bindings_at = now
          Rails.logger.warn({ code: "monitoring.source_discovery_unavailable" }.to_json)
        end
        @bindings || {}
      end
    end

    def self.invalidate_bindings
      @bindings_at = 0
    end
    def self.record(code, related: {}, delivery: false, exception: nil)
      return unless Current.correlation_id
      command_id = Current.command&.dig(:command_id)
      related = related.merge(business_command_id: command_id) if command_id.to_s.match?(UUID)
      observation = {
        source_observation_id: SecureRandom.uuid, code: code, component: "tom-web",
        correlation_id: Current.correlation_id, observed_at: Time.current.utc.iso8601(6), related: related
      }
      diagnostic = { code: code, correlation_id: Current.correlation_id }
      if exception
        diagnostic[:exception_class] = exception.class.name
        diagnostic[:frames] = Array(exception.backtrace_locations).first(6).map { |f| { file: File.basename(f.path), line: f.lineno, label: f.base_label.to_s.gsub(/[^A-Za-z0-9_?!:.]/, "_")[0, 80] } }
      end
      Rails.logger.public_send(code == "application.exception" ? :error : :info, diagnostic.to_json)
      mapping = sources
      source = mapping[Current.scope] || mapping["global"]
      unless source
        Rails.logger.warn({ code: "monitoring.persistence_unconfigured", correlation_id: Current.correlation_id }.to_json)
        return
      end
      observation = observation.merge(source_id: source)
      if exception
        observation[:diagnostic] = { exception_class: exception.class.name, frames: diagnostic[:frames].map { |f| f.merge(file: f[:file].gsub(/[^A-Za-z0-9_.-]/, "_")) } }
      end
      spool = Spool.instance
      queued = spool&.enqueue(observation, delivery: delivery)
      Rails.logger.warn({ code: "monitoring.spool_rejected", correlation_id: Current.correlation_id }.to_json) if spool && !queued
      result = Ep::Client.new(instrument: false, timeout: 0.5).report_observation(observation, delivery: delivery)
      spool.acknowledge_id(observation[:source_observation_id]) if queued
      result
    rescue StandardError
      # Independent local evidence, no recursion, no raw exception/provider/input text.
      Rails.logger.warn({ code: "monitoring.capture_unavailable", correlation_id: Current.correlation_id }.to_json)
      nil
    end
  end
end
