class InvitationsController < ApplicationController
  before_action :require_session
  def index
    render Views::Invitations::Inbox.new(invitations: ep.incoming_invitations.fetch("invitations"), signed_in: true, notice: flash[:notice], alert: flash[:alert])
  end
end
