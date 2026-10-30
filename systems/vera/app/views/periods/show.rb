class Views::Periods::Show < Views::Base
  def initialize(**options)
    super(**options)
    @options = options.except(:signed_in, :notice, :alert)
  end
  def view_template
    render Components::Periods.new(**@options)
  end
end
