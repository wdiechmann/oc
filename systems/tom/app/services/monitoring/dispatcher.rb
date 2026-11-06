module Monitoring
  class Dispatcher
    def self.heartbeat_path
      Rails.root.join("tmp", Rails.env.test? ? "test-monitoring-alert-heartbeat-#{Process.pid}" : "monitoring-alert-heartbeat")
    end
    def self.heartbeat_fresh?
      last = Integer(File.read(heartbeat_path), exception: false)
      !!(last && (Time.current.to_i-last).between?(0, 30))
    rescue SystemCallError, IOError
      false
    end
    def self.tick
      Current.set(correlation_id: SecureRandom.uuid, scope: nil, command: nil, reported: true) do
        client = Ep::Client.new(instrument: false)
        alerts = client.claim_monitoring_alerts(SecureRandom.uuid).fetch("alerts")
        alerts.each do |material|
          status = begin
            Notifications::Delivery.monitoring_alert(material)
          rescue Notifications::Delivery::Error
            "unknown"
          end
          outcome = { source_observation_id: material.fetch("attempt_id"), alert_id: material.fetch("alert_id"), attempt_id: material.fetch("attempt_id"), status: status }
          spool = Spool.instance
          queued = spool&.enqueue(outcome, kind: "alert_outcome")
          begin
            client.monitoring_alert_outcome(material.fetch("alert_id"), material.fetch("attempt_id"), status)
            spool.acknowledge_id(material.fetch("attempt_id")) if queued
          rescue Ep::Client::Error, Ep::Client::Unavailable
            Rails.logger.warn({ code: "monitoring.alert_ack_pending", alert_id: material.fetch("alert_id") }.to_json)
          end
        end
        path = heartbeat_path
        temporary = Pathname.new(path.to_s+".#{SecureRandom.uuid}")
        File.open(temporary, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |f| f.write(Time.current.to_i.to_s); f.flush; f.fsync }
        File.rename(temporary, path)
        alerts.length
      end
    end
  end
end
