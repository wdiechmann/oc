require "net/http"
require "json"

module Ep
  class Client
    def initialize(origin: ENV.fetch("EP_BASE_URL", "http://localhost:4000"))
      @origin = URI.parse(origin)
      local = %w[localhost 127.0.0.1 ::1].include?(@origin.hostname)
      valid = %w[http https].include?(@origin.scheme) && @origin.hostname && !@origin.userinfo && [ "", "/" ].include?(@origin.path) && !@origin.query && !@origin.fragment
      raise ArgumentError, "EP_BASE_URL must be an HTTPS origin or a loopback HTTP origin" unless valid && (@origin.scheme == "https" || local)
    end

    # This public EP readiness endpoint needs neither a user session nor a backend token.
    # Future business operations must bind VERA's own backend credential and current EP user authority.
    def ready?
      uri = @origin.dup
      uri.path = "/health/ready"
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 1
      http.read_timeout = 2
      http.write_timeout = 2
      http.max_retries = 0
      response = http.request(request)
      return false unless response.code == "200"
      body = JSON.parse(response.body)
      body.is_a?(Hash) && body["status"] == "ready"
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError
      false
    end
  end
end
