class HomeController < ApplicationController
  def index
    if signed_in?
      page Views::Home::Workspace, workspaces: ep.workspaces
    else
      reset_session if session[:ep_token]
      page Views::Home::Index
    end
  end
end
