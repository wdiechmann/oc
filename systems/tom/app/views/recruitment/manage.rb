class Views::Recruitment::Manage < Views::Base
  def initialize(data:, applications:, tenant_id:, occasion_id:, key:, values: {}, **options)
    super(**options)
    @data, @applications, @tid, @oid, @key, @values = data, applications, tenant_id, occasion_id, key, values
  end

  def view_template
    a(href: tenant_occasion_path(@tid, @oid), class: "text-sm font-medium text-emerald-800 hover:underline") { "← Occasion overview" }
    h1(class: "mt-8 text-4xl font-semibold tracking-tight") { "Recruitment · #{@data.fetch('name')}" }
    p(class: "mt-4 text-stone-600") { "Current intake state: #{@data.fetch('recruitment_state').capitalize}" }
    p(class: "mt-4 text-amber-900") { "The expiry review deadline has been reached. New intake is blocked." } if @data["expired"]
    section(class: "mt-8 max-w-2xl rounded-2xl border border-stone-200 bg-white p-8") do
      if @data["recruitment_state"] == "open"
        h2(class: "text-xl font-semibold") { "Recruitment is open" }
        a(href: recruitment_path(@tid, @data.fetch("slug")), class: "mt-4 inline-block font-semibold text-emerald-800 hover:underline") { "Open application page" }
        p(class: "mt-3 text-sm text-stone-500") { "Share the application page address. Signing in verifies identity; submitting an application does not grant membership or an assignment." }
        form_with(url: close_tenant_occasion_recruitment_path(@tid, @oid)) do |f|
          f.hidden_field(:idempotency_key, value: @key)
          div(class: "mt-6") do
            f.label(:reason, "Reason for closing", class: "text-sm font-medium")
            f.text_field(:reason, required: true, maxlength: 500, value: @values["reason"], class: FIELD)
          end
          f.submit("Close recruitment", class: BUTTON)
        end
      elsif !@data["expired"]
        h2(class: "text-xl font-semibold") { "Prepare and open recruitment" }
        config = @data.fetch("config", {}).merge(@values)
        form_with(url: open_tenant_occasion_recruitment_path(@tid, @oid)) do |f|
          f.hidden_field(:idempotency_key, value: @key)
          div(class: "mt-6") do
            f.label(:title, "Public recruitment title", class: "text-sm font-medium")
            f.text_field(:title, required: true, maxlength: 120, value: config["title"], class: FIELD)
          end
          div(class: "mt-6") do
            f.label(:instructions, "Public application instructions", class: "text-sm font-medium")
            f.text_area(:instructions, required: true, maxlength: 2000, rows: 5, value: config["instructions"], class: FIELD)
          end
          div(class: "mt-6") do
            f.label(:privacy_notice_url, "Recruitment privacy notice URL (HTTPS)", class: "text-sm font-medium")
            f.url_field(:privacy_notice_url, required: true, value: config["privacy_notice_url"], class: FIELD)
          end
          div(class: "mt-6 flex items-start gap-3") do
            f.check_box(:confirm_manual_review, required: true, class: "mt-1 size-4 accent-emerald-900")
            f.label(:confirm_manual_review, "Applications require manual review and lead vouching; safeguarding and qualification checks are required before appointments or assignments.", class: "text-sm leading-relaxed")
          end
          p(class: "mt-4 text-xs text-stone-500") { "This opens expressions of interest only. Admission, vouching and assignment review are separate workflows and remain pending." }
          f.submit("Open recruitment", class: BUTTON)
        end
      end
    end
    section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8") do
      h2(class: "text-2xl font-semibold") { "Applications awaiting review" }
      p(class: "mt-3 text-sm text-stone-500") { "Up to 100 recent applications. This step records interest only; no admission actions are available yet." }
      if @applications.empty?
        p(class: "mt-6 text-stone-500") { "No applications yet." }
      else
        ul(class: "mt-5 divide-y divide-stone-200") do
          @applications.each do |application|
            li(class: "flex flex-wrap justify-between gap-3 py-4") do
              span(class: "break-all font-medium") { application.fetch("email") }
              span(class: "text-sm text-stone-500") { "Pending review" }
            end
          end
        end
      end
    end
  end
end
