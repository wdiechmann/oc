module Monitoring
  class Reconciliation
    def self.token(session)
      command = Current.command
      return unless command && command[:type] && command[:key]
      session[:monitoring_nonce] ||= SecureRandom.uuid
      verifier.generate({ type: command[:type], key: command[:key], nonce: session[:monitoring_nonce], operation_id: Current.operation_id, correlation_id: Current.correlation_id }, expires_in: 10.minutes, purpose: "command-status")
    end

    def self.read(token, session)
      data = verifier.verified(token.to_s, purpose: "command-status")
      return unless data.is_a?(Hash) && session[:monitoring_nonce].present? && data["nonce"] == session[:monitoring_nonce]
      data
    end

    def self.verifier = Rails.application.message_verifier("monitoring-reconciliation")
  end
end
