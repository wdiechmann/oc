require "mail"
require "uri"
require "json"
require "fileutils"
require "digest"

module Notifications
  class Delivery
    class Error < StandardError; end

    def self.magic_link(material)
      return unless material
      origin = public_origin
      token = material.fetch("token")
      link = "#{origin}/session/verify?#{URI.encode_www_form(token: token)}"
      send_message(material.fetch("email"), "Sign in to TOM", "Confirm your TOM sign-in using this link:\n\n#{link}\n\nExpires: #{material.fetch('expires_at')}\nOpening the link does not sign you in until you confirm. If you did not request it, ignore it.", "magic-#{Digest::SHA256.hexdigest(token)}")
    rescue KeyError, URI::InvalidURIError, ArgumentError
      raise Error, "Invalid sign-in delivery material", cause: nil
    end

    def self.invitation(material)
      return unless material
      occasion = material["occasion_id"].present?
      role = occasion ? "occasion" : "tenant"
      name = occasion ? material.fetch("occasion_name") : material.fetch("tenant_name")
      text = "You are invited to administer #{role} #{name} in #{material.fetch('tenant_name')}.\n\nSign in to TOM using #{material.fetch('email')}, then review and accept the invitation:\n#{public_origin}/invitations\n\nInvitation expires: #{material.fetch('expires_at')}\nThis message grants no access by itself."
      send_message(material.fetch("email"), "TOM #{role}-admin invitation: #{name}", text, "invitation-#{material.fetch('invitation_id')}")
    rescue KeyError, URI::InvalidURIError, ArgumentError
      raise Error, "Invalid invitation delivery material", cause: nil
    end

    def self.public_origin
      origin = ENV.fetch("TOM_PUBLIC_BASE_URL", Rails.env.test? ? "http://www.example.com" : "http://localhost:3000")
      uri = URI.parse(origin)
      valid = %w[http https].include?(uri.scheme) && uri.host && uri.userinfo.nil? && [ "", "/" ].include?(uri.path) && uri.query.nil? && uri.fragment.nil?
      raise Error, "Invalid TOM_PUBLIC_BASE_URL" unless valid
      raise Error, "HTTPS is required in production" if Rails.env.production? && uri.scheme != "https"
      origin.delete_suffix("/")
    end

    def self.send_message(recipient, subject, text, id)
      method = Rails.env.test? ? "test" : ENV.fetch("TOM_DELIVERY_METHOD", Rails.env.development? ? "file" : "smtp")
      from = ENV.fetch("TOM_MAIL_FROM", Rails.env.production? ? "" : "tom@localhost")
      raise Error, "TOM_MAIL_FROM is required" if from.empty?
      raise Error, "Invalid message identifier" unless id.match?(/\A[A-Za-z0-9_.-]{1,200}\z/)
      subject = subject.gsub(/[\r\n]+/, " ")
      message = Mail.new
      message.from, message.to, message.subject, message.body = from, recipient, subject, text
      message.message_id = "#{id}@#{URI.parse(public_origin).host}"
      case method
      when "file"
        raise Error, "File delivery is development-only" unless Rails.env.development?
        dir = Rails.root.join("tmp", "outbox")
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, dir)
        path = dir.join("#{id}.json")
        File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
          file.chmod(0o600)
          file.write(JSON.generate(to: recipient, subject: subject, text: text))
        end
      when "test"
        raise Error, "Test delivery is unavailable" unless Rails.env.test?
        message.delivery_method(:test)
        message.deliver!
      when "smtp"
        host = ENV.fetch("TOM_SMTP_HOST")
        ssl = ENV["TOM_SMTP_SSL"] == "true"
        message.delivery_method(:smtp, address: host, port: Integer(ENV.fetch("TOM_SMTP_PORT", ssl ? "465" : "587")), domain: URI.parse(public_origin).host, user_name: ENV["TOM_SMTP_USERNAME"], password: ENV["TOM_SMTP_PASSWORD"], authentication: ENV["TOM_SMTP_USERNAME"].present? ? :plain : nil, enable_starttls: !ssl, ssl: ssl, open_timeout: 5, read_timeout: 10)
        message.deliver!
      else
        raise Error, "Unknown delivery method"
      end
      true
    rescue StandardError
      # Do not propagate SMTP/provider exceptions containing recipient or credential details.
      raise Error, "Message delivery failed", cause: nil
    end
    private_class_method :send_message
  end
end
