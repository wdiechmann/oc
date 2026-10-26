class Views::Monitoring::Index < Views::Base
  def initialize(tenant_id:, kind:, filters:, data:, **options)
    super(**options)
    @content = { tenant_id: tenant_id, kind: kind, filters: filters, data: data }
  end
  def view_template
    div(id: "monitoring-list") { render Components::MonitoringList.new(**@content) }
  end
end
