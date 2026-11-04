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

    def vat_rules(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/vat-rules")
    def vat_rule_command(tid, bid, action, attrs, key)
      suffix = action == "revise" ? "/#{uuid!(attrs[:rule_id])}" : ""
      request(action == "revise" ? :patch : :post, "#{book_root(tid)}/#{uuid!(bid)}/vat-rules#{suffix}", body: attrs.except(:rule_id), key: key)
    end
    def catalogues(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/setup/catalogues")
    def catalogue_command(tid, bid, action, attrs, key)
      suffix = case action
      when "initialize" then "/initialize"
      when "create" then ""
      when "revise" then "/#{uuid!(attrs[:entry_id])}"
      end
      request(action == "revise" ? :patch : :post, "#{book_root(tid)}/#{uuid!(bid)}/setup/catalogues#{suffix}", body: attrs.except(:entry_id), key: key)
    end
    def periods(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/periods")
    def period_command(tid, bid, action, attrs, key)
      id = attrs[:period_id]
      suffix = action == "create" ? "" : "/#{uuid!(id)}#{action == 'revise' ? '' : "/#{action}"}"
      request(action == "revise" ? :patch : :post, "#{book_root(tid)}/#{uuid!(bid)}/periods#{suffix}", body: attrs.except(:period_id), key: key)
    end
    def formula_preview(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/formula-preview")
    def calculate_formula_preview(tid, bid, attrs) = request(:post, "#{book_root(tid)}/#{uuid!(bid)}/formula-preview", body: attrs)
    def chart_order(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/chart-order")
    def preview_chart_order(tid, bid, attrs) = request(:post, "#{book_root(tid)}/#{uuid!(bid)}/chart-order/reviews", body: attrs)
    def chart_order_review(tid, bid, id) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/chart-order/reviews/#{uuid!(id)}")
    def accept_chart_order(tid, bid, attrs, key) = request(:post, "#{book_root(tid)}/#{uuid!(bid)}/chart-order/reviews/#{uuid!(attrs[:review_id])}/accept", body: attrs.except(:review_id), key: key)
    def chart_import_info(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/chart-imports")
    def chart_export(tid, bid, query = {}) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/chart-export", query: query)
    def upload_chart(tid, bid, data) = request(:post, "#{book_root(tid)}/#{uuid!(bid)}/chart-imports", body: data)
    def chart_import(tid, bid, id) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/chart-imports/#{uuid!(id)}")
    def preview_chart(tid, bid, id, mapping, create_codes: false, mode: "replace") = request(:post, "#{book_root(tid)}/#{uuid!(bid)}/chart-imports/#{uuid!(id)}/preview", body: { mapping: mapping, create_codes: create_codes, mode: mode })
    def accept_chart(tid, bid, attrs, key)
      request(:post, "#{book_root(tid)}/#{uuid!(bid)}/chart-imports/#{uuid!(attrs[:import_id])}/accept", body: attrs.except(:import_id), key: key)
    end
    def chart_accounts(tid, bid, query = {}) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/setup/accounts", query: query.compact)
    def finance_setup(tid, bid) = request(:get, "#{book_root(tid)}/#{uuid!(bid)}/setup")
    def configure_finance(tid, bid, action, attrs, key)
      suffix = { "reopening_authority"=>"reopening-authority", "steward"=>"stewards", "binding"=>"bindings", "account_create"=>"accounts", "account_revise"=>"accounts/#{uuid!(attrs[:account_id]) if action == 'account_revise'}" }.fetch(action)
      body = attrs.except(:account_id)
      request(action == "account_revise" ? :patch : :post, "#{book_root(tid)}/#{uuid!(bid)}/setup/#{suffix}", body: body, key: key)
    end
    def books(tid) = request(:get, book_root(tid))
    def book(tid, id) = request(:get, "#{book_root(tid)}/#{uuid!(id)}")
    def create_book(tid, attrs, key) = request(:post, book_root(tid), body: attrs, key: key)
    def revise_book(tid, id, attrs, key) = request(:patch, "#{book_root(tid)}/#{uuid!(id)}", body: attrs, key: key)
    def book_receipt(type, key) = request(:get, "/me/commands", query: { command_type: type, idempotency_key: key })

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

    def uuid!(id)
      raise Error.new(404) unless id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)
      id
    end
    def book_root(tid) = "/tenants/#{uuid!(tid)}/finance/books"

    def backend_token
      return Rails.application.config.x.ep_backend_token if Rails.env.test?
      token = ENV["VERA_EP_BACKEND_TOKEN"].presence
      path = Rails.root.join("config", "ep_backend_token")
      token ||= File.read(path).strip if Rails.env.development? && File.file?(path)
      token ||= ENV["EP_BACKEND_TOKEN"].presence if Rails.env.production?
      token
    end

    def request(method, path, body: nil, key: nil, query: nil)
      credential = backend_token
      raise Unavailable, "VERA backend credential is missing" unless credential.is_a?(String) && credential.bytesize >= 32
      uri = @origin.dup
      uri.path = "/api/v1#{path}"
      uri.query = URI.encode_www_form(query) if query
      request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method).new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-EP-Backend-Token"] = credential
      request["Authorization"] = "Bearer #{@token}" if @token
      request["X-Correlation-ID"] = SecureRandom.uuid
      request["Idempotency-Key"] = key if key
      request.body = JSON.generate(body) if body
      response = connection(uri).request(request)
      payload = JSON.parse(response.body)
      raise Unavailable, "EP returned an invalid response" unless payload.is_a?(Hash)
      raise Unavailable, "EP backend authentication is unavailable" if payload["error"] == "backend_authentication_required"
      raise Error.new(response.code.to_i, code: payload["error"]) unless response.code.to_i.between?(200, 299)
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
