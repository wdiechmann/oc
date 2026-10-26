class Components::UpdateStream < Components::Base
  register_element :turbo_stream
  def initialize(target:, component:, operation_id: nil)
    @target, @component, @operation_id = target, component, operation_id
  end
  def view_template
    turbo_stream(action: "update", target: @target, data: { operation_id: @operation_id }) { template { render @component } }
  end
end
