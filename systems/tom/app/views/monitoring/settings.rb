class Views::Monitoring::Settings < Views::Base
  def initialize(content:, **options)
    super(**options)
    @content = content
  end
  def view_template
    div(id: "monitoring-settings") { render Components::MonitoringSettings.new(**@content) }
  end
end
