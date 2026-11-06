class Components::FeedbackStream < Components::Base
  include Phlex::Rails::Helpers::FormWith
  register_element :turbo_stream
  def initialize(message:, check_url: nil, retry_url: nil)
    @message, @check, @retry = message, check_url, retry_url
  end
  def view_template
    turbo_stream(action: "append", target: "vera-feedback") do
      template { render Components::Toast.new(message: @message, kind: "alert", check_url: @check, retry_url: @retry) }
    end
  end
end
