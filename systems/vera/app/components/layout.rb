class Components::Layout < Components::Base
  include Phlex::Rails::Helpers::CSRFMetaTags
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::StylesheetLinkTag
  include Phlex::Rails::Helpers::JavascriptIncludeTag
  include Phlex::Rails::Helpers::FormWith

  def initialize(signed_in: false, notice: nil, alert: nil)
    @signed_in, @notice, @alert = signed_in, notice, alert
  end

  def view_template(&block)
    doctype
    html(lang: "en") do
      head do
        title { "VERA · Financial Control" }
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        meta(name: "turbo-cache-control", content: "no-cache")
        meta(name: "turbo-prefetch", content: "false")
        link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
        csrf_meta_tags
        csp_meta_tag
        stylesheet_link_tag "tailwind", "application"
        javascript_include_tag "turbo", type: "module", defer: true
        javascript_include_tag "chart_order_editor", type: "module", defer: true
        javascript_include_tag "chart_editor", type: "module", defer: true
      end
      body(class: "min-h-screen bg-stone-50 text-stone-900 antialiased") do
        header(class: "border-b border-stone-200 bg-white") do
          div(class: "mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-5") do
            a(href: root_path, class: "flex items-center gap-3 font-semibold tracking-tight", aria_label: "VERA home") do
              span(class: "rounded-xl bg-teal-950 px-3 py-2 text-white") { "V" }
              span { "VERA" }
            end
            if @signed_in
              form_with(url: session_path, method: :delete) { |f| f.submit("Sign out", class: "cursor-pointer text-sm font-medium text-teal-900 hover:underline") }
            else
              a(href: new_session_path, class: "text-sm font-medium text-teal-900 hover:underline") { "Sign in" }
            end
          end
        end
        main(id: "main-content", class: "mx-auto max-w-6xl px-6 py-12 sm:py-20") do
          div(id: "vera-feedback", aria_live: "polite", aria_atomic: "true") do
            p(role: "status", class: "mb-6 rounded-xl border border-teal-200 bg-teal-50 p-4") { @notice } if @notice
            p(role: "alert", class: "mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4") { @alert } if @alert
          end
          yield
        end
        footer(class: "mx-auto max-w-6xl border-t border-stone-200 px-6 py-6 text-xs text-stone-500") do
          plain "One financial workspace for every occasion."
        end
      end
    end
  end
end
