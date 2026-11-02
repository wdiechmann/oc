class Views::Catalogues::Show < Views::Base
  def initialize(**options)
    super(**options)
    @options = options.except(:signed_in, :notice, :alert)
  end
  def view_template
    render Components::Catalogues.new(**@options)
  end
end
