class Components::CataloguesStream < Components::Base
  register_element :turbo_stream
  def initialize(**options) = @options = options
  def view_template
    turbo_stream(action: "update", target: "vera-feedback") { template { } }
    turbo_stream(action: "replace", target: "vera-book-content") { template { render Components::Catalogues.new(**@options) } }
  end
end
