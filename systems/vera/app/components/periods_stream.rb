class Components::PeriodsStream < Components::Base
  register_element :turbo_stream
  def initialize(**options) = @options = options
  def view_template
    turbo_stream(action: "update", target: "vera-feedback") { template { } }
    turbo_stream(action: "replace", target: "vera-book-content") do
      template { render Components::Periods.new(**@options) }
    end
  end
end
