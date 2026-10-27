class HomeController < ApplicationController
  def index
    response.headers["Cache-Control"] = "no-store"
    render Views::Home::Index.new
  end
end
