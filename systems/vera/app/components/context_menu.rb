class Components::ContextMenu < Components::Base
  register_element :context_menu
  def initialize(id:, label:, hidden: false)
    @id, @label, @hidden = id, label, hidden
  end
  def view_template(&block)
    context_menu(class: "block", hidden: @hidden) do
      button(type: "button", title: @label, aria: { label: @label, haspopup: "menu", expanded: "false", controls: @id }, data: { menu_trigger: true }, class: "inline-flex rounded p-2 text-stone-600 hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-teal-800") { render Components::Icons::More.new }
      div(id: @id, role: "menu", aria_label: @label, popover: "auto", data: { context_menu: true }, class: "vera-context-menu") { yield }
    end
  end
end
