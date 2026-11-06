class Views::Recruitment::Landing < Views::Base
  def initialize(data:, tenant_id:, slug:, key:, **options)
    super(public_page: true, **options)
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
      div(class: "mt-6") do
        a(href: config.fetch("privacy_notice_url"), class: "block font-semibold text-emerald-800 underline", rel: "noopener noreferrer") { "Read the recruitment privacy notice" }
      end
      form_with(url: @signed_in ? recruitment_applications_path(@tid, @slug) : new_session_path, method: @signed_in ? :post : :get, class: "mt-6 space-y-5") do |f|
        if @signed_in
          f.hidden_field(:idempotency_key, value: @key)
          f.hidden_field(:notice_version, value: config.fetch("notice_version"))
        end
        div(class: "flex items-start gap-3") do
          f.check_box(:acknowledge_notice, required: true, class: "mt-1 size-5 shrink-0 accent-emerald-900")
          f.label(:acknowledge_notice, "I have read the recruitment privacy notice and want to apply for this occasion.", class: "min-w-0 text-sm leading-relaxed")
        end
        div do
          f.submit(@signed_in ? "Submit application" : "Sign in to apply", class: "block w-full cursor-pointer rounded-lg bg-emerald-900 px-5 py-3 text-center text-sm font-semibold text-white hover:bg-emerald-800 focus:outline-2 focus:outline-offset-2 focus:outline-emerald-800 sm:w-auto")
        end
      end
    end
  end
end
