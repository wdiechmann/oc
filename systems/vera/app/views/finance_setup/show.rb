class Views::FinanceSetup::Show < Views::Base
  def initialize(**options)
    super(**options)
    @options = options.except(:notice, :alert, :signed_in, :dialog)
  end
  def view_template
    render Components::FinanceSetup.new(**@options)
  end
end
