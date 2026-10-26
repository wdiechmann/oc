class Views::Monitoring::Show < Views::Base
  def initialize(tenant_id:, id:, occasion_id:, data:, timeline:, key:, **options)
    super(**options)
    @content = { tenant_id: tenant_id, id: id, occasion_id: occasion_id, data: data, timeline: timeline, key: key }
  end
  def view_template
    div(id: "monitoring-detail") { render Components::MonitoringDetail.new(**@content) }
  end
end
