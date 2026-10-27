class EpHealthController < ActionController::Base
  def show
    ready = Ep::Client.new.ready?
    response.headers["Cache-Control"] = "no-store"
    render json: { status: ready ? "ready" : "unavailable" }, status: ready ? :ok : :service_unavailable
  end
end
