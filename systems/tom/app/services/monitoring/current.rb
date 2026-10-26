module Monitoring
  class Current < ActiveSupport::CurrentAttributes
    attribute :correlation_id, :operation_id, :scope, :command, :reported
  end
end
