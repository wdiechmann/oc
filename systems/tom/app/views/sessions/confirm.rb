class Views::Sessions::Confirm < Views::Base
  def view_template
    section(class: "max-w-lg rounded-2xl border border-stone-200 bg-white p-8") do
      h1(class: "text-3xl font-semibold") { "Confirm your sign-in" }
      p(class: "mt-4 text-stone-600") { "Continue to sign in to TOM. This link can be used once." }
      form_with(url: session_path) { |f| f.submit("Confirm sign-in", class: BUTTON) }
    end
  end
end
