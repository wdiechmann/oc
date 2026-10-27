require "mail"
require "uri"
require "json"
require "fileutils"
require "digest"

module Notifications
  class Delivery
    class Error < StandardError; end
    def self.tom_origin = origin("TOM_BASE_URL", "http://localhost:3000")

    def self.origin(key, default)
      value = ENV.fetch(key, default)
      uri = URI.parse(value)
      local = %w[localhost 127.0.0.1 ::1].include?(uri.hostname)
      valid = %w[http https].include?(uri.scheme) && uri.hostname && !uri.userinfo && [ "", "/" ].include?(uri.path) && !uri.query && !uri.fragment
      raise Error, "Invalid application origin" unless valid && (uri.scheme == "https" || (local && !Rails.env.production?))
      value.delete_suffix("/")
    rescue URI::InvalidURIError
      raise Error, "Invalid application origin", cause: nil
    end

    def self.magic_link(material)
      return unless material
      token, email = material.fetch("token"), material.fetch("email")
      raise Error unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{32,128}\z/) && email.is_a?(String) && email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
      public_origin = origin("VERA_PUBLIC_BASE_URL", "http://localhost:3001")
      link = "#{public_origin}/session/verify?#{URI.encode_www_form(token: token)}"
      text = "Confirm your VERA sign-in:\n\n#{link}\n\nExpires: #{material.fetch('expires_at')}\nOpening the link does not sign you in until you confirm. Ignore this message if you did not request it."
      id = "magic-#{Digest::SHA256.hexdigest(token)}"
      method = Rails.env.test? ? "test" : ENV.fetch("VERA_DELIVERY_METHOD", Rails.env.development? ? "file" : "smtp")
      if method == "file"
        raise Error unless Rails.env.development?
        dir = Rails.root.join("tmp", "outbox")
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, dir)
        File.open(dir.join("#{id}.json"), File::WRONLY|File::CREAT|File::TRUNC, 0o600) do |f|
          f.chmod(0o600)
          f.write(JSON.generate(to: email, subject: "Sign in to VERA", text: text))
        end
      else
        message = Mail.new
        message.from = ENV.fetch("VERA_MAIL_FROM", Rails.env.production? ? "" : "vera@localhost")
        raise Error if message.from.blank?
        message.to, message.subject, message.body = email, "Sign in to VERA", text
        message.message_id = "#{id}@#{URI.parse(public_origin).hostname}"
        case method
        when "test"
          raise Error unless Rails.env.test?
          message.delivery_method(:test)
        when "smtp"
          ssl = ENV["VERA_SMTP_SSL"] == "true"
          message.delivery_method(:smtp, address: ENV.fetch("VERA_SMTP_HOST"), port: Integer(ENV.fetch("VERA_SMTP_PORT", ssl ? "465" : "587")), domain: URI.parse(public_origin).hostname, user_name: ENV["VERA_SMTP_USERNAME"], password: ENV["VERA_SMTP_PASSWORD"], authentication: ENV["VERA_SMTP_USERNAME"].present? ? :plain : nil, enable_starttls: !ssl, ssl: ssl, open_timeout: 5, read_timeout: 10)
        else
          raise Error
        end
        message.deliver!
      end
      true
    rescue StandardError
      raise Error, "Sign-in message delivery was not confirmed", cause: nil
    end
  end
end
