require Rails.root.join("..", "monitor", "lib", "ep_monitor", "spool").to_s
module Monitoring
  class Spool
    def self.instance
      configured = Rails.application.config.x.monitoring_spool
      return configured if configured.is_a?(EpMonitor::Spool)
      return nil if Rails.env.test?
      directory = ENV["TOM_MONITOR_SPOOL_DIR"].presence || (Rails.root.join("tmp", "monitoring-spool").to_s if Rails.env.development?)
      key = ENV["TOM_MONITOR_SPOOL_KEY"].presence
      if Rails.env.development? && !key
        path = Rails.root.join("config", "monitoring_spool_key")
        unless File.file?(path)
          begin
            File.open(path, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |f| f.write(Base64.strict_encode64(SecureRandom.random_bytes(32))); f.flush; f.fsync }
          rescue Errno::EEXIST
            nil
          end
        end
        key = File.read(path).strip
      end
      return nil unless directory && key
      @mutex ||= Mutex.new
      @mutex.synchronize do
        @instance = nil if @signature != [ directory, key ]
        @signature = [ directory, key ]
        @instance ||= EpMonitor::Spool.new(directory: directory, key: key)
      end
    end
  end
end
