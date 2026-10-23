class SessionsController < ApplicationController
  def new
    page Views::Sessions::New
  end

  def verify
    token = params[:token].to_s
    unless token.match?(/\A[A-Za-z0-9_-]{32,128}\z/)
      redirect_to new_session_path, alert: "That sign-in link is invalid. Request a new one."
      return
    end
    session[:pending_magic_token] = token
    redirect_to confirm_session_path, status: :see_other
  end

  def confirm
    unless session[:pending_magic_token]
      redirect_to new_session_path
      return
    end
    page Views::Sessions::Confirm
  end

  def create
    token = params[:token].presence || session[:pending_magic_token]
    result = Ep::Client.new.verify(token.to_s.strip)
    expiry = Time.iso8601(result.fetch("expires_at"))
    return_to = session[:recruitment_return_to] || session[:sign_in_return_to]
    reset_session
    session[:ep_token] = result.fetch("token")
    session[:expires_at] = expiry.to_i
    redirect_to(return_to.is_a?(String) && (return_to.start_with?("/recruitment/") || return_to == invitations_path) ? return_to : root_path, status: :see_other)
  end

  def destroy
    reset_session
    redirect_to new_session_path, status: :see_other
  end
end
