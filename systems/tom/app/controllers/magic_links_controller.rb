class MagicLinksController < ApplicationController
  def create
    Ep::Client.new.request_link(params[:email].to_s.strip)
    redirect_to new_session_path, notice: "Check your email for your sign-in message.", status: :see_other
  end
end
