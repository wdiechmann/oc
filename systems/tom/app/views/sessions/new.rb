class Views::Sessions::New < Views::Base
  def view_template
    div(class: "grid gap-14 lg:grid-cols-2 lg:gap-24") do
      section(class: "pt-4") do
        p(class: "mb-5 text-xs font-bold uppercase tracking-widest text-emerald-800") { "Good things begin together" }
        h1(class: "max-w-lg text-5xl font-semibold tracking-tight leading-tight md:text-6xl") { "Your camp starts here." }
        p(class: "mt-6 max-w-md text-lg leading-relaxed text-stone-600") { "One place to establish your organization and lay the foundation for your next occasion." }
        div(class: "mt-10 flex gap-3 text-sm text-stone-500") do
          span(class: "font-semibold text-emerald-800") { "01" }
          span { "Sign in" }; span { "→" }; span { "Create a tenant" }; span { "→" }; span { "Build together" }
        end
      end
      section(class: "rounded-2xl border border-stone-200 bg-white p-7 shadow-sm md:p-9") do
        h2(class: "text-2xl font-semibold tracking-tight") { "Welcome to TOM" }
        p(class: "mt-2 text-sm text-stone-600") { "Sign in with your email. No password needed." }
        form_with(url: magic_links_path) do |f|
          div(class: "mt-7") do
            f.label(:email, "Email address", class: "text-sm font-medium")
            f.email_field(:email, required: true, autocomplete: "email", placeholder: "you@example.org", class: FIELD)
            f.submit("Send sign-in message", class: BUTTON)
          end
        end
        div(class: "mt-8 border-t border-stone-200 pt-7") do
          h3(class: "font-medium") { "Already have your sign-in token?" }
          p(class: "mt-2 text-sm leading-relaxed text-stone-500") { "Enter the single-use token from your sign-in message." }
          p(class: "mt-2 text-xs text-stone-500") { "Local development: find the token in EP’s private tmp/magic_links mailbox." } if Rails.env.development?
          form_with(url: session_path) do |f|
            div(class: "mt-4") do
              f.label(:token, "Sign-in token", class: "text-sm font-medium")
              f.password_field(:token, required: true, autocomplete: "off", class: FIELD)
              f.submit("Continue securely", class: BUTTON)
            end
          end
        end
      end
    end
  end
end
