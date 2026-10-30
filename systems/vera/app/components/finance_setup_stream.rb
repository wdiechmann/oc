class Components::FinanceSetupStream < Components::Base
  register_element :turbo_stream
  def initialize(**options)
    @options = options.except(:signed_in)
  end
  def view_template
    turbo_stream(action: "replace", target: "vera-book-content") do
      template { render Components::FinanceSetup.new(**@options) }
    end
  end
end
