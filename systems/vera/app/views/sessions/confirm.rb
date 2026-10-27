class Views::Sessions::Confirm < Views::Base
  def view_template
    section(class: "mx-auto max-w-lg rounded-2xl border border-stone-200 bg-white p-8") do
      h1(class: "text-3xl font-semibold") { "Confirm your VERA sign-in" }
      p(class: "mt-4 text-sm leading-relaxed text-stone-600") { "Continue to use your existing identity in VERA. Opening the email link alone does not sign you in." }
      form_with(url: session_path) { |f| f.submit("Continue to VERA", class: BUTTON) }
    end
  end
end
