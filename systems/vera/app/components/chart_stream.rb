class Components::ChartStream < Components::Base
  register_element :turbo_stream
  def initialize(**options) = @options = options
  def view_template
    turbo_stream(action: "replace", target: "vera-book-content") do
      template { render Components::Chart.new(**@options) }
    end
  end
end
