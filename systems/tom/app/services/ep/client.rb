require "net/http"
require "json"

module Ep
  class Client
    class Error < StandardError
      attr_reader :status, :code
      def initialize(status, code: nil)
        @status, @code = status, code
        super("EP request failed (#{status})")
      end
    end
    class Unavailable < StandardError; end

    def initialize(token: nil)
      @token = token
      @origin = URI(ENV.fetch("EP_BASE_URL", "http://localhost:4000"))
      unless %w[http https].include?(@origin.scheme) && @origin.host && @origin.userinfo.nil? && [ "", "/" ].include?(@origin.path) && @origin.query.nil? && @origin.fragment.nil?
        raise ArgumentError, "EP_BASE_URL must be an HTTP(S) origin"
      end
      raise ArgumentError, "EP requires HTTPS in production" if Rails.env.production? && @origin.scheme != "https"
    end

    def request_link(email) = request(:post, "/auth/magic-links", body: { email: email })
    def verify(token) = request(:post, "/auth/magic-links/verify", body: { token: token })
    def create_tenant(name, key) = request(:post, "/tenants", body: { name: name }, key: key)

    def tenant(id)
      raise Error.new(404) unless id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
      request(:get, "/tenants/#{id}")
    end

    def occasions(tenant_id)
      uuid!(tenant_id)
      request(:get, "/tenants/#{tenant_id}/occasions")
    end

    def occasion(tenant_id, id)
      uuid!(tenant_id)
      uuid!(id)
      request(:get, "/tenants/#{tenant_id}/occasions/#{id}")
    end

    def create_occasion(tenant_id, attributes, key)
      uuid!(tenant_id)
      request(:post, "/tenants/#{tenant_id}/occasions", body: attributes, key: key)
    end

    def incoming_invitations = request(:get, "/me/tenant-admin-invitations")

    def incoming_occasion_invitations = request(:get, "/me/occasion-admin-invitations")

    def admin_invitations(tenant_id, occasion_id: nil)
      uuid!(tenant_id)
      request(:get, invitation_collection(tenant_id, occasion_id))
    end

    def invite_admin(tenant_id, email, key, occasion_id: nil)
      uuid!(tenant_id)
      request(:post, invitation_collection(tenant_id, occasion_id), body: { email: email }, key: key)
    end

    def invitation_action(tenant_id, invitation_id, action, key, occasion_id: nil)
      uuid!(tenant_id)
      uuid!(invitation_id)
      raise ArgumentError unless %w[accept revoke].include?(action)
      request(:post, "#{invitation_collection(tenant_id, occasion_id)}/#{invitation_id}/#{action}", body: {}, key: key)
    end

    private

    def invitation_collection(tenant_id, occasion_id)
      uuid!(tenant_id)
      return "/tenants/#{tenant_id}/admin-invitations" unless occasion_id
      uuid!(occasion_id)
      "/tenants/#{tenant_id}/occasions/#{occasion_id}/admin-invitations"
    end

    def uuid!(id)
      raise Error.new(404) unless id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
    end

    def request(method, path, body: nil, key: nil)
      uri = @origin.dup
      uri.path = "/api/v1#{path}"
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 8
      http.write_timeout = 8
      http.max_retries = 0
      req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@token}" if @token
      req["Idempotency-Key"] = key if key
      req.body = JSON.generate(body) if body
      response = http.request(req)
      payload = JSON.parse(response.body)
      raise Unavailable, "Invalid EP response" unless payload.is_a?(Hash)
      raise Error.new(response.code.to_i, code: payload["error"]) unless response.code.to_i.between?(200, 299)
      payload
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, JSON::ParserError
      raise Unavailable, "EP is temporarily unavailable"
    end
  end
end
