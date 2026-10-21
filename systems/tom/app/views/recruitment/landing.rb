class Views::Recruitment::Landing < Views::Base
  def initialize(data:, tenant_id:, slug:, key:, **options)
    super(**options)
    @data, @tid, @slug, @key, @signed_in = data, tenant_id, slug, key, options[:signed_in]
  end
  def view_template
    if @data["status"] != "ready"
      h1(class: "text-4xl font-semibold") { "Preparing recruitment information" }
      a(href: recruitment_path(@tid, @slug), class: "mt-6 inline-block text-emerald-800 hover:underline") { "Refresh" }
      return
    end
    config = @data.fetch("config")
    p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { @data.fetch("name") }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { config.fetch("title") }
    section(class: "mt-8 max-w-2xl rounded-2xl border border-stone-200 bg-white p-8") do
      p(class: "whitespace-pre-line leading-relaxed text-stone-600") { config.fetch("instructions") }
      p(class: "mt-6 text-sm text-stone-500") { "Your application will be pending manual review and lead vouching. It does not make you a member or appoint you to a role. Safeguarding and qualification checks apply before assignment." }
      a(href: config.fetch("privacy_notice_url"), class: "mt-5 inline-block font-semibold text-emerald-800 hover:underline", rel: "noopener noreferrer") { "Read the recruitment privacy notice" }
      if @signed_in
        form_with(url: recruitment_applications_path(@tid, @slug)) do |f|
          f.hidden_field(:idempotency_key, value: @key)
          f.hidden_field(:notice_version, value: config.fetch("notice_version"))
          div(class: "mt-6 flex items-start gap-3") do
            f.check_box(:acknowledge_notice, required: true, class: "mt-1 size-4 accent-emerald-900")
            f.label(:acknowledge_notice, "I have read the recruitment privacy notice and want to apply for this occasion.", class: "text-sm leading-relaxed")
          end
          f.submit("Submit application", class: BUTTON)
        end
      else
        a(href: new_session_path, class: "mt-6 inline-block rounded-lg bg-emerald-900 px-5 py-3 font-semibold text-white hover:bg-emerald-800") { "Sign in to apply" }
      end
    end
  end
end
