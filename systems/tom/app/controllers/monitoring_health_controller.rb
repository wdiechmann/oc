class MonitoringHealthController < ActionController::API
  def show
    path = Monitoring::Dispatcher.heartbeat_path
    last = File.file?(path) ? Integer(File.read(path), exception: false) : nil
    ready = last && (Time.current.to_i-last).between?(0, 30)
    response.headers["Cache-Control"] = "no-store"
    render json: { ready: !!ready }, status: ready ? 200 : 503
  end
end
