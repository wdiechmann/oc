require "net/http"
require "uri"
require "json"
require "openssl"

module EpMonitor
  class Client
    def initialize(origin:, token:)
      @origin = URI(origin)
      @token = token
      valid = %w[http https].include?(@origin.scheme) && @origin.host && !@origin.userinfo && ["", "/"].include?(@origin.path) && !@origin.query && !@origin.fragment
      raise ArgumentError, "Invalid EP origin" unless valid && token.to_s.bytesize >= 32
      raise ArgumentError, "Non-local EP must use HTTPS" if @origin.scheme != "https" && !%w[localhost 127.0.0.1 ::1].include?(@origin.host)
    end
    def post(path, body)
      uri = @origin.dup; uri.path = "/api/v1#{path}"
      request = Net::HTTP::Post.new(uri)
      request["X-EP-Backend-Token"] = @token
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.generate(body)
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 1; http.read_timeout = 2; http.write_timeout = 2; http.max_retries = 0
      response = http.request(request)
      response.code.to_i
    end
    def self.probe(url, allow_remote: false)
      uri = URI(url)
      local = %w[localhost 127.0.0.1 ::1].include?(uri.host)
      raise ArgumentError unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && (local || (allow_remote && uri.scheme == "https"))
      http = Net::HTTP.new(uri.host,uri.port,nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 1; http.read_timeout = 2; http.write_timeout = 2; http.max_retries = 0
      response = http.get(uri.request_uri)
      response.code.to_i == 200
    rescue StandardError
      false
    end
  end
end
