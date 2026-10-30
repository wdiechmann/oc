class Views::ChartAccounts::Show < Views::Base
  def initialize(**options)
    super(**options)
    @options = options.except(:signed_in, :notice, :alert)
  end
  def view_template
    render Components::Chart.new(**@options)
  end
end
