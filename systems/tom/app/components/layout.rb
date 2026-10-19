class Components::Layout < Components::Base
  include Phlex::Rails::Helpers::CSRFMetaTags
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::StylesheetLinkTag
  include Phlex::Rails::Helpers::FormWith

  def initialize(signed_in: false, notice: nil, alert: nil)
    @signed_in, @notice, @alert = signed_in, notice, alert
  end

  def view_template(&block)
    doctype
    html(lang: "en") do
      head do
        title { "TOM · Tenant & Occasion Management" }
        link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        csrf_meta_tags
        csp_meta_tag
        stylesheet_link_tag "tailwind", "application"
      end
      body(class: "min-h-screen bg-stone-50 text-stone-900 antialiased") do
        header(class: "border-b border-stone-200 bg-white") do
          div(class: "mx-auto flex max-w-6xl items-center justify-between px-6 py-5") do
            a(href: root_path, class: "flex items-center gap-3 font-bold tracking-tight") do
              span(class: "rounded-xl bg-emerald-900 px-3 py-2 text-white") { "T" }
              span { "TOM" }
              span(class: "hidden text-sm font-normal text-stone-500 sm:inline") { "Tenant & Occasion Management" }
            end
            if @signed_in
              a(href: invitations_path, class: "text-sm font-medium text-emerald-800 hover:underline") { "Invitations" }
              form_with(url: session_path, method: :delete) { |f| f.submit("Sign out", class: "cursor-pointer text-sm font-medium text-stone-600 hover:text-emerald-800") }
            end
          end
        end
        main(class: "mx-auto max-w-6xl px-6 py-12 md:py-20") do
          p(role: "status", class: "mb-8 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-900") { @notice } if @notice
          p(role: "alert", class: "mb-8 rounded-xl border border-amber-200 bg-amber-50 p-4") { @alert } if @alert
          yield
        end
        footer(class: "mx-auto max-w-6xl border-t border-stone-200 px-6 py-6 text-xs text-stone-500") { "A shared foundation for every occasion." }
      end
    end
  end
end
