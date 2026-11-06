class MonitoringHealthController < ActionController::API
  def show
    ready = Monitoring::Dispatcher.heartbeat_fresh?
    response.headers["Cache-Control"] = "no-store"
    render json: { ready: !!ready }, status: ready ? 200 : 503
  end
end
