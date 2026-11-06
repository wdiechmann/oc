class Components::Layout < Components::Base
  include Phlex::Rails::Helpers::CSRFMetaTags
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::StylesheetLinkTag
  include Phlex::Rails::Helpers::JavascriptIncludeTag
  include Phlex::Rails::Helpers::FormWith

  def initialize(signed_in: false, notice: nil, alert: nil, public_page: false)
    @public_page = public_page
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
        meta(name: "turbo-cache-control", content: "no-cache")
        meta(name: "turbo-prefetch", content: "false")
        javascript_include_tag "turbo", type: "module", defer: true
        javascript_include_tag "monitoring", type: "module", defer: true
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
              a(href: monitoring_path, class: "text-sm font-medium text-emerald-800 hover:underline") { "Monitoring" }
              a(href: invitations_path, class: "text-sm font-medium text-emerald-800 hover:underline") { "Invitations" }
              form_with(url: session_path, method: :delete) { |f| f.submit("Sign out", class: "cursor-pointer text-sm font-medium text-stone-600 hover:text-emerald-800") }
            end
          end
        end unless @public_page
        main(class: "mx-auto max-w-6xl px-6 py-12 md:py-20") do
          p(role: "status", class: "mb-8 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-900") do
              if Rails.env.development? && @notice.is_a?(Hash)
                plain @notice["message"] || @notice[:message]
                plain " · "
                a(href: @notice["sign_in_url"] || @notice[:sign_in_url], class: "font-semibold underline", data: { turbo: false }) { "Sign in to TOM" }
              else
                plain @notice
              end
            end if @notice
          p(role: "alert", class: "mb-8 rounded-xl border border-amber-200 bg-amber-50 p-4") { @alert } if @alert
          div(id: "tom-feedback", aria_live: "polite", aria_atomic: "true")
          div(id: "tom-content") { yield }
        end
        footer(class: "mx-auto max-w-6xl border-t border-stone-200 px-6 py-6 text-xs text-stone-500") { "A shared foundation for every occasion." } unless @public_page
      end
    end
  end
end
