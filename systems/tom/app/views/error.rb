class Views::Error < Views::Base
  def initialize(message:, **options)
    super(**options)
    @message = message
  end

  def view_template
    section(class: "max-w-2xl rounded-2xl border border-stone-200 bg-white p-9") do
      h1(class: "text-3xl font-semibold") { @message == "Tenant unavailable" ? @message : "We couldn’t complete that request" }
      p(role: "alert", class: "mt-5 leading-relaxed text-stone-600") { @message }
      a(href: root_path, class: "mt-7 inline-block font-semibold text-emerald-800 hover:underline") { "Return to TOM" }
    end
  end
end
