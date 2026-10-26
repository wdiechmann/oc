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

    def initialize(token: nil, instrument: true, timeout: nil)
      @token, @instrument, @timeout = token, instrument, timeout
      @origin = URI(ENV.fetch("EP_BASE_URL", "http://localhost:4000"))
      unless %w[http https].include?(@origin.scheme) && @origin.host && @origin.userinfo.nil? && [ "", "/" ].include?(@origin.path) && @origin.query.nil? && @origin.fragment.nil?
        raise ArgumentError, "EP_BASE_URL must be an HTTP(S) origin"
      end
      raise ArgumentError, "EP requires HTTPS in production" if Rails.env.production? && @origin.scheme != "https"
    end

    def request_link(email)
      backend!
      delivery_response(request(:post, "/auth/magic-links", body: { email: email }))
    end
    def verify(token)
      backend!
      request(:post, "/auth/magic-links/verify", body: { token: token })
    end
    def workspaces = request(:get, "/me/workspaces")
    def create_tenant(name, key)
      track_command("CreateTenant", key)
      request(:post, "/tenants", body: { name: name }, key: key)
    end

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
      track_command("CreateOccasion", key)
      request(:post, "/tenants/#{tenant_id}/occasions", body: attributes, key: key)
    end

    def incoming_invitations = request(:get, "/me/tenant-admin-invitations")

    def incoming_occasion_invitations = request(:get, "/me/occasion-admin-invitations")

    def admin_invitations(tenant_id, occasion_id: nil)
      uuid!(tenant_id)
      request(:get, invitation_collection(tenant_id, occasion_id))
    end

    def invite_admin(tenant_id, email, key, occasion_id: nil)
      backend!
      uuid!(tenant_id)
      track_command(occasion_id ? "InviteOccasionAdmin" : "InviteTenantAdmin", key)
      delivery_response(request(:post, invitation_collection(tenant_id, occasion_id), body: { email: email }, key: key))
    end

    def invitation_action(tenant_id, invitation_id, action, key, occasion_id: nil)
      uuid!(tenant_id)
      uuid!(invitation_id)
      raise ArgumentError unless %w[accept revoke].include?(action)
      track_command("#{action.capitalize}#{occasion_id ? 'Occasion' : 'Tenant'}AdminInvitation", key)
      request(:post, "#{invitation_collection(tenant_id, occasion_id)}/#{invitation_id}/#{action}", body: {}, key: key)
    end

    def recruitment(tenant_id, occasion_id)
      request(:get, recruitment_collection(tenant_id, occasion_id))
    end

    def recruitment_applications(tenant_id, occasion_id)
      request(:get, "#{recruitment_collection(tenant_id, occasion_id)}/applications")
    end

    def recruitment_command(tenant_id, occasion_id, action, attrs, key)
      raise ArgumentError unless %w[open close applications].include?(action)
      track_command({ "open" => "OpenOccasionRecruitment", "close" => "CloseOccasionRecruitment", "applications" => "SubmitRecruitmentApplication" }.fetch(action), key)
      request(:post, "#{recruitment_collection(tenant_id, occasion_id)}/#{action}", body: attrs, key: key)
    end

    def recruitment_landing(tenant_id, slug)
      uuid!(tenant_id)
      raise Error.new(404) unless slug.to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) && slug.bytesize <= 64
      request(:get, "/recruitment/#{tenant_id}/#{slug}")
    end

    def report_observation(attributes, delivery: false)
      backend!
      request(:post, delivery ? "/monitoring/delivery-outcomes" : "/monitoring/observations", body: attributes)
    end

    def monitoring_list(tenant_id, kind, filters = {})
      uuid!(tenant_id)
      raise ArgumentError unless %w[issues observations timeline].include?(kind)
      request(:get, "/tenants/#{tenant_id}/monitoring/#{kind}", query: filters)
    end

    def monitoring_issue(tenant_id, id)
      uuid!(tenant_id)
      uuid!(id)
      request(:get, "/tenants/#{tenant_id}/monitoring/issues/#{id}")
    end

    def monitoring_action(tenant_id, id, attributes, key)
      uuid!(tenant_id)
      uuid!(id)
      track_command("MonitoringAction:#{id}", key)
      request(:post, "/tenants/#{tenant_id}/monitoring/issues/#{id}/actions", body: attributes, key: key)
    end

    def command_status(type, key)
      request(:get, "/me/commands", query: { command_type: type, idempotency_key: key })
    end

    private

    def track_command(type, key)
      Monitoring::Current.command = { type: type, key: key, accepted: false } if @instrument && Monitoring::Current.correlation_id
    end

    def track_acceptance(path, payload)
      return unless Monitoring::Current.correlation_id
      return if path.include?("/monitoring") || path.start_with?("/me/") || path.start_with?("/auth/") || path.start_with?("/recruitment/")
      ids = path.match(%r{\A/tenants/([0-9a-f-]{36})(?:/occasions/([0-9a-f-]{36}))?}i)
      tid, oid = payload["tenant_id"] || ids&.[](1), payload["occasion_id"] || ids&.[](2)
      if tid.to_s.match?(Monitoring::Reporter::UUID)
        Monitoring::Current.scope = "tenant:#{tid.downcase}#{":occasion:#{oid.downcase}" if oid.to_s.match?(Monitoring::Reporter::UUID)}"
      end
      if Monitoring::Current.command && payload["command_id"].to_s.match?(Monitoring::Reporter::UUID)
        Monitoring::Current.command = Monitoring::Current.command.merge(accepted: true, command_id: payload["command_id"])
      end
    end

    def observe_failure(status, path)
      return unless @instrument && !path.include?("/monitoring") && !path.start_with?("/me/commands")
      code = case status
      when 400, 422, 429 then "request.validation_rejected"
      when 401, 403, 404 then "request.permission_denied"
      when 409 then "request.conflict"
      else "dependency.unavailable"
      end
      Monitoring::Current.reported = true
      Monitoring::Reporter.record(code)
    end

    def recruitment_collection(tenant_id, occasion_id)
      uuid!(tenant_id)
      uuid!(occasion_id)
      "/tenants/#{tenant_id}/occasions/#{occasion_id}/recruitment"
    end

    def invitation_collection(tenant_id, occasion_id)
      uuid!(tenant_id)
      return "/tenants/#{tenant_id}/admin-invitations" unless occasion_id
      uuid!(occasion_id)
      "/tenants/#{tenant_id}/occasions/#{occasion_id}/admin-invitations"
    end

    def uuid!(id)
      raise Error.new(404) unless id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
    end

    def delivery_response(response)
      raise Unavailable, "EP delivery contract is unavailable" unless response.key?("delivery")
      response
    end

    def configured_backend_token
      return Rails.application.config.x.ep_backend_token if Rails.env.test?
      configured = Rails.application.config.x.ep_backend_token
      token = ENV["EP_BACKEND_TOKEN"].presence || (configured if configured.is_a?(String))
      path = Rails.root.join("config", "ep_backend_token")
      token ||= File.read(path).strip if Rails.env.development? && File.file?(path)
      token
    end

    def backend!
      token = configured_backend_token
      raise Unavailable, "EP backend credential is missing" unless token.is_a?(String) && token.bytesize >= 32
      token
    end

    def request(method, path, body: nil, key: nil, query: nil)
      uri = @origin.dup
      uri.path = "/api/v1#{path}"
      uri.query = URI.encode_www_form(query) if query.present?
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout || 3
      http.read_timeout = @timeout || 8
      http.write_timeout = @timeout || 8
      http.max_retries = 0
      req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      backend_token = configured_backend_token
      req["X-EP-Backend-Token"] = backend_token if backend_token.present?
      req["X-Correlation-ID"] = Monitoring::Current.correlation_id if Monitoring::Current.correlation_id
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@token}" if @token
      req["Idempotency-Key"] = key if key
      req.body = JSON.generate(body) if body
      response = http.request(req)
      payload = JSON.parse(response.body)
      raise Unavailable, "Invalid EP response" unless payload.is_a?(Hash)
      raise Unavailable, "EP backend authentication unavailable" if payload["error"] == "backend_authentication_required"
      unless response.code.to_i.between?(200, 299)
        observe_failure(response.code.to_i, path)
        raise Error.new(response.code.to_i, code: payload["error"])
      end
      track_acceptance(path, payload) if @instrument
      payload
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, JSON::ParserError
      observe_failure(503, path)
      raise Unavailable, "EP is temporarily unavailable", cause: nil
    end
  end
end
