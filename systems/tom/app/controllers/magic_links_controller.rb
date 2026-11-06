class MagicLinksController < ApplicationController
  def create
    result = Ep::Client.new.request_link(params[:email].to_s.strip)
    delivered = Notifications::Delivery.magic_link(result["delivery"])
    notice = "Check your email for your sign-in message."
    notice = { message: "Development sign-in link", sign_in_url: delivered } if Rails.env.development? && delivered.is_a?(String)
    redirect_to new_session_path, notice: notice, status: :see_other
  end
end
