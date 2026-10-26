module Monitoring
  module Paths
    def monitoring_list_path(tenant, **options)
      tenant ? tenant_monitoring_path(tenant, **options) : platform_monitoring_path(**options)
    end
    def monitoring_issue_path(tenant, id, **options)
      tenant ? tenant_monitoring_issue_path(tenant, id, **options) : platform_monitoring_issue_path(id, **options)
    end
    def monitoring_issue_action_path(tenant, id)
      tenant ? tenant_monitoring_issue_action_path(tenant, id) : platform_monitoring_issue_action_path(id)
    end
    def monitoring_settings_path(tenant, **options)
      tenant ? tenant_monitoring_settings_path(tenant, **options) : platform_monitoring_settings_path(**options)
    end
  end
end
