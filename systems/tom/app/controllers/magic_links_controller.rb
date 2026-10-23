class MagicLinksController < ApplicationController
  def create
    result = Ep::Client.new.request_link(params[:email].to_s.strip)
    Notifications::Delivery.magic_link(result["delivery"])
    redirect_to new_session_path, notice: "Check your email for your sign-in message.", status: :see_other
  end
end
