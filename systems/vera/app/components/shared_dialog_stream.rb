class Components::SharedDialogStream < Components::Base
  register_element :turbo_stream
  def initialize(content:, journal: nil, body: nil)
    @content, @journal, @body = content, journal, body
  end
  def view_template
    if @journal || @body
      turbo_stream(action: "replace", target: "vera-book-content", data: { preserve_journal_draft: !!@journal }) { template { render(@journal || @body) } }
    end
    turbo_stream(action: "update", target: "shared-dialog-host") do
      template { render Components::SharedContentDialog.new(content: @content) }
    end
  end
end
