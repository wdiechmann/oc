class SessionsController < ApplicationController
  def new
    page Views::Sessions::New
  end

  def request_link
    result = Ep::Client.new.request_link(params[:email].to_s.strip)
    raise Ep::Client::Unavailable unless result.key?("delivery")
    session.delete(:pending_magic_token)
    Notifications::Delivery.magic_link(result["delivery"])
    redirect_to new_session_path, notice: "If your identity is registered, check your email for your VERA sign-in link.", status: :see_other
  end

  def verify
    token = params[:token].to_s
    unless token.match?(/\A[A-Za-z0-9_-]{32,128}\z/)
      session.delete(:pending_magic_token)
      redirect_to new_session_path, alert: "That sign-in link is invalid. Copy the complete URL from the newest VERA message."
      return
    end
    session[:pending_magic_token] = token
    redirect_to confirm_session_path, status: :see_other
  end

  def confirm
    return redirect_to(new_session_path) unless session[:pending_magic_token]
    page Views::Sessions::Confirm
  end

  def create
    return redirect_to(new_session_path) unless session[:pending_magic_token]
    result = Ep::Client.new.verify(session[:pending_magic_token])
    expiry = Time.iso8601(result.fetch("expires_at"))
    raise Ep::Client::Unavailable unless expiry > Time.current && result["token"].is_a?(String)
    reset_session
    session[:ep_token], session[:expires_at] = result.fetch("token"), expiry.to_i
    redirect_to root_path, status: :see_other
  rescue Ep::Client::Error => error
    raise unless error.status == 401
    reset_session
    redirect_to new_session_path, alert: "This sign-in link has expired, was already used, or was replaced by a newer request. Request one new link and open the newest VERA message; earlier VERA links and TOM links will not work here.", status: :see_other
  end

  def destroy
    notice = "You have signed out of VERA."
    begin
      ep.sign_out if session[:ep_token]
    rescue Ep::Client::Unavailable, Ep::Client::Error
      notice = "Signed out in this browser. EP session revocation was not confirmed; that session will expire automatically."
    ensure
      reset_session
    end
    redirect_to new_session_path, notice: notice, status: :see_other
  end
end
