class SessionsController < ApplicationController
  def new
    page Views::Sessions::New
  end

  def create
    result = Ep::Client.new.verify(params[:token].to_s.strip)
    expiry = Time.iso8601(result.fetch("expires_at"))
    return_to = session[:recruitment_return_to]
    reset_session
    session[:ep_token] = result.fetch("token")
    session[:expires_at] = expiry.to_i
    redirect_to(return_to.is_a?(String) && return_to.start_with?("/recruitment/") ? return_to : root_path, status: :see_other)
  end

  def destroy
    reset_session
    redirect_to new_session_path, status: :see_other
  end
end
