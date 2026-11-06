class Components::BookDetailsDialog < Components::Base
  def initialize(**options)
    @options = options
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Name and hierarchy" }
    render Components::BookForm.new(**@options)
  end
end
