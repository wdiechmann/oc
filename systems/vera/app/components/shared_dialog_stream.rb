class Components::SharedDialogStream < Components::Base
  register_element :turbo_stream
  def initialize(content:, journal: nil)
    @content, @journal = content, journal
  end
  def view_template
    if @journal
      turbo_stream(action: "replace", target: "vera-book-content") { template { render @journal } }
    end
    turbo_stream(action: "update", target: "shared-dialog-host") do
      template { render Components::SharedContentDialog.new(content: @content) }
    end
  end
end
