class Components::SharedContentDialog < Components::Base
  register_element :shared_dialog
  def initialize(content:)
    @content = content
  end
  def view_template
    shared_dialog do
      dialog(id: "shared-content-dialog", aria_labelledby: "shared-dialog-title", class: "vera-shared-dialog") do
        button(type: "button", data: { dialog_close: true }, aria_label: "Close dialog", class: "float-right rounded px-3 py-2 text-sm text-teal-900 underline") { "Close" }
        render @content
      end
    end
  end
end
