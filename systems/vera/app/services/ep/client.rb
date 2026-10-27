require "net/http"
require "json"

module Ep
  class Client
    class Error < StandardError
      attr_reader :status
      def initialize(status)
        @status = status
        super("EP request failed (#{status})")
      end
    end
    class Unavailable < StandardError; end
    def initialize(token: nil, origin: ENV.fetch("EP_BASE_URL", "http://localhost:4000"))
      @token = token
      @origin = URI.parse(origin)
      local = %w[localhost 127.0.0.1 ::1].include?(@origin.hostname)
      valid = %w[http https].include?(@origin.scheme) && @origin.hostname && !@origin.userinfo && [ "", "/" ].include?(@origin.path) && !@origin.query && !@origin.fragment
      raise ArgumentError, "EP_BASE_URL must be an HTTPS origin or a loopback HTTP origin" unless valid && (@origin.scheme == "https" || local)
    end

    def request_link(email)
      request(:post, "/auth/sign-in-links", body: { email: email })
    end
    def verify(token) = request(:post, "/auth/magic-links/verify", body: { token: token })
    def workspaces = request(:get, "/me/workspaces")
    def sign_out = request(:delete, "/auth/session")

    # This public EP readiness endpoint needs neither a user session nor a backend token.
    def ready?
      uri = @origin.dup
      uri.path = "/health/ready"
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      response = connection(uri).request(request)
      return false unless response.code == "200"
      body = JSON.parse(response.body)
      body.is_a?(Hash) && body["status"] == "ready"
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError
      false
    end

    private

    def backend_token
      return Rails.application.config.x.ep_backend_token if Rails.env.test?
      token = ENV["VERA_EP_BACKEND_TOKEN"].presence
      path = Rails.root.join("config", "ep_backend_token")
      token ||= File.read(path).strip if Rails.env.development? && File.file?(path)
      token ||= ENV["EP_BACKEND_TOKEN"].presence if Rails.env.production?
      token
    end

    def request(method, path, body: nil)
      credential = backend_token
      raise Unavailable, "VERA backend credential is missing" unless credential.is_a?(String) && credential.bytesize >= 32
      uri = @origin.dup
      uri.path = "/api/v1#{path}"
      request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method).new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-EP-Backend-Token"] = credential
      request["Authorization"] = "Bearer #{@token}" if @token
      request["X-Correlation-ID"] = SecureRandom.uuid
      request.body = JSON.generate(body) if body
      response = connection(uri).request(request)
      payload = JSON.parse(response.body)
      raise Unavailable, "EP returned an invalid response" unless payload.is_a?(Hash)
      raise Unavailable, "EP backend authentication is unavailable" if payload["error"] == "backend_authentication_required"
      raise Error.new(response.code.to_i) unless response.code.to_i.between?(200, 299)
      payload
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError
      raise Unavailable, "EP is unavailable", cause: nil
    end

    def connection(uri)
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 1
      http.read_timeout = 2
      http.write_timeout = 2
      http.max_retries = 0
      http
    end
  end
end
