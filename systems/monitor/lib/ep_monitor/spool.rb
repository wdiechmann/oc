require "openssl"
require "base64"
require "json"
require "fileutils"
require "securerandom"

module EpMonitor
  # Durable transport only. Business/monitoring truth remains in EP.
  class Spool
    UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i
    class Invalid < StandardError; end
    attr_reader :directory

    def initialize(directory:, key:, max_files: 10_000, max_bytes: 64 * 1024 * 1024, max_age: 86_400, clock: -> { Time.now.to_i })
      @directory = File.expand_path(directory)
      @key = Base64.strict_decode64(key.to_s)
      raise Invalid, "A stable base64-encoded 32-byte spool key is required" unless @key.bytesize == 32
      @max_files, @max_bytes, @max_age, @clock = max_files, max_bytes, max_age, clock
      raise Invalid, "Invalid spool bounds" unless max_files.positive? && max_bytes.positive? && max_age.between?(60, 30 * 86_400)
      FileUtils.mkdir_p(@directory, mode: 0o700)
      raise Invalid, "Spool directory must be private and not a symlink" if File.lstat(@directory).symlink? || File.stat(@directory).mode & 0o077 != 0
    rescue ArgumentError
      raise Invalid, "Invalid spool key", cause: nil
    end

    def enqueue(observation, delivery: false, kind: nil)
      id = observation[:source_observation_id] || observation["source_observation_id"]
      raise Invalid, "Invalid observation ID" unless id.is_a?(String) && id.match?(UUID)
      raise Invalid, "Invalid transport kind" unless [nil, "alert_outcome"].include?(kind)
      body = { "observation" => observation, "delivery" => delivery }
      body["kind"] = kind if kind
      plaintext = JSON.generate(canonical(body))
      raise Invalid, "Observation exceeds transport limit" if plaintext.bytesize > 32_768
      synchronized do
        expire!
        existing = files.find { |path| File.basename(path).start_with?(id.downcase + ".") }
        if existing
          raise Invalid, "Changed content for an existing observation" unless decrypt(existing).fetch("body") == JSON.parse(plaintext)
          next true
        end
        payload = encrypt({ "created_at" => @clock.call, "body" => JSON.parse(plaintext) })
        if files.length >= @max_files || files.sum { |f| File.size(f) } + payload.bytesize > @max_bytes
          count!("full")
          next false
        end
        atomic_write(File.join(@directory, "#{id.downcase}.pending"), payload)
        true
      end
    end

    def claim
      synchronized do
        expire!
        # A crashed drainer's lease expires; ingestion replay uses the original ID.
        Dir.glob(File.join(@directory, "*.inflight")).each do |path|
          File.rename(path, path.sub(/\.inflight\z/, ".pending")) if @clock.call - File.mtime(path).to_i >= 60
        end
        path = Dir.glob(File.join(@directory, "*.pending")).min_by { |file| [File.mtime(file), file] }
        next nil unless path
        claimed = path.sub(/\.pending\z/, ".inflight")
        File.rename(path, claimed)
        File.utime(Time.at(@clock.call), Time.at(@clock.call), claimed)
        begin
          { path: claimed, body: decrypt(claimed).fetch("body") }
        rescue Invalid, JSON::ParserError, KeyError
          File.rename(claimed, claimed.sub(/\.inflight\z/, ".quarantine"))
          count!("unreadable")
          nil
        end
      end
    end

    def acknowledge_id(id)
      raise Invalid unless id.to_s.match?(UUID)
      synchronized do
        path = File.join(@directory,"#{id.downcase}.pending")
        File.unlink(path) if File.file?(path)
      end
    end

    def acknowledge(record)
      finish(record) { |path| File.unlink(path) }
    end

    def retry_later(record)
      finish(record) { |path| File.rename(path, path.sub(/\.inflight\z/, ".pending")) }
    end

    def quarantine(record)
      finish(record) do |path|
        File.rename(path, path.sub(/\.inflight\z/, ".quarantine"))
        count!("rejected")
      end
    end

    def statistics
      synchronized do
        expire!
        paths = files
        { pending: paths.count { |f| f.end_with?(".pending") }, inflight: paths.count { |f| f.end_with?(".inflight") },
          quarantined: paths.count { |f| f.end_with?(".quarantine") }, bytes: paths.sum { |f| File.size(f) },
          losses: counters }
      end
    end

    private

    def canonical(value)
      case value
      when Hash then value.map { |k,v| [k.to_s, canonical(v)] }.sort.to_h
      when Array then value.map { |v| canonical(v) }
      else value
      end
    end

    def synchronized
      File.open(File.join(@directory, ".lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        raise Invalid, "Spool is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def files
      Dir.glob(File.join(@directory, "*.{pending,inflight,quarantine}"))
    end

    def finish(record)
      path = record.fetch(:path)
      raise Invalid unless File.dirname(path) == @directory && File.basename(path).match?(/\A[0-9a-f-]{36}\.inflight\z/)
      synchronized { yield path if File.file?(path) }
    end

    def encrypt(value)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = @key
      nonce = SecureRandom.random_bytes(12)
      cipher.iv = nonce
      cipher.auth_data = "ep-monitor-spool-v1"
      encrypted = cipher.update(JSON.generate(value)) + cipher.final
      JSON.generate(v: 1, nonce: Base64.strict_encode64(nonce), tag: Base64.strict_encode64(cipher.auth_tag), data: Base64.strict_encode64(encrypted))
    end

    def decrypt(path)
      raise Invalid if File.lstat(path).symlink? || File.size(path) > 65_536
      payload = JSON.parse(File.read(path))
      raise Invalid unless payload.fetch("v") == 1
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = @key
      cipher.iv = Base64.strict_decode64(payload.fetch("nonce"))
      cipher.auth_tag = Base64.strict_decode64(payload.fetch("tag"))
      cipher.auth_data = "ep-monitor-spool-v1"
      JSON.parse(cipher.update(Base64.strict_decode64(payload.fetch("data"))) + cipher.final)
    rescue OpenSSL::Cipher::CipherError, ArgumentError
      raise Invalid, "Spool content cannot be authenticated", cause: nil
    end

    def expire!
      paths = files
      cursor = @expiry_cursor || 0
      selected = paths.rotate(cursor).first(64)
      @expiry_cursor = paths.empty? ? 0 : (cursor+selected.length) % paths.length
      selected.each do |path|
        begin
          expired = @clock.call - decrypt(path).fetch("created_at") > @max_age
        rescue Invalid, JSON::ParserError, KeyError
          # Keep corrupt/key-mismatched evidence quarantined, bounded by total quota.
          next
        end
        if expired
          File.unlink(path)
          count!("expired")
        end
      end
    end

    def counters
      path = File.join(@directory, ".losses")
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    end

    def count!(reason)
      values = counters
      values[reason] = values.fetch(reason, 0) + 1
      atomic_write(File.join(@directory, ".losses"), JSON.generate(values))
    end

    def atomic_write(path, data)
      temporary = File.join(@directory, ".tmp-#{SecureRandom.uuid}")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(data); file.flush; file.fsync }
      File.rename(temporary, path)
      File.open(@directory) { |dir| dir.fsync }
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end
end
