class Views::Sessions::New < Views::Base
  def view_template
    section(class: "mx-auto max-w-lg rounded-2xl border border-stone-200 bg-white p-7 sm:p-9") do
      p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { "One identity, every system" }
      h1(class: "mt-4 text-3xl font-semibold tracking-tight") { "Sign in to VERA" }
      p(class: "mt-3 text-sm leading-relaxed text-stone-600") { "Use the same email as your existing TOM identity. We’ll send a single-use sign-in link; no password is needed." }
      form_with(url: link_session_path) do |f|
        f.label(:email, "Email address", class: "mt-6 block text-sm font-medium")
        f.email_field(:email, required: true, autocomplete: "email", class: FIELD)
        f.submit("Send sign-in link", class: BUTTON)
      end
      p(class: "mt-5 text-xs leading-relaxed text-stone-500") { "Invitations, new identities and account recovery are managed in TOM." }
      a(href: Notifications::Delivery.tom_origin, class: "mt-3 inline-block text-sm font-medium text-teal-900 hover:underline", data: { turbo: false }) { "Open TOM" }
      p(class: "mt-4 text-xs text-stone-500") { "Local development: open the sign-in link in VERA’s private tmp/outbox message." } if Rails.env.development?
    end
  end
end
