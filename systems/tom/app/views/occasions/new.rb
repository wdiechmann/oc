class Views::Occasions::New < Views::Base
  def initialize(tenant_id:, key:, values: {}, **options)
    super(**options)
    @tenant_id, @key, @values = tenant_id, key, values
  end

  def view_template
    a(href: tenant_path(@tenant_id), class: "text-sm font-medium text-emerald-800 hover:underline") { "← Tenant overview" }
    section(class: "mt-8 max-w-2xl rounded-2xl border border-stone-200 bg-white p-8 md:p-10") do
      p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "The next gathering" }
      h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Create an occasion" }
      p(class: "mt-4 leading-relaxed text-stone-600") { "Set up a camp or other occasion within your tenant. It will begin as a draft, with recruitment closed." }
      form_with(url: tenant_occasions_path(@tenant_id)) do |f|
        f.hidden_field(:idempotency_key, value: @key)
        div(class: "mt-7") do
          f.label(:name, "Occasion name", class: "text-sm font-medium")
          f.text_field(:name, required: true, maxlength: 120, value: @values["name"], placeholder: "Spejdernes Lejr 2030", class: FIELD)
        end
        div(class: "mt-6") do
          f.label(:slug, "Short name", class: "text-sm font-medium")
          f.text_field(:slug, required: true, maxlength: 64, pattern: "[a-z0-9]+(-[a-z0-9]+)*", value: @values["slug"], placeholder: "sl2030", class: FIELD, aria: { describedby: "slug-help" })
          p(id: "slug-help", class: "mt-2 text-xs text-stone-500") { "Lowercase letters, numbers and hyphens. Must be unique within this tenant. This name does not grant access." }
        end
        div(class: "mt-6") do
          f.label(:expires_on, "Expiry review date (UTC)", class: "text-sm font-medium")
          f.date_field(:expires_on, required: true, min: Date.current.iso8601, value: @values["expires_on"], class: FIELD)
          p(class: "mt-2 text-xs leading-relaxed text-stone-500") { "The end of this date is recorded for retention review. It is not the camp’s start or end date. Review tasks and retirement processing will be added separately." }
        end
        div(class: "mt-7 flex items-start gap-3") do
          f.check_box(:assign_self_as_admin, checked: @values.fetch("assign_self_as_admin", "1") == "1", class: "mt-1 size-4 accent-emerald-900")
          div do
            f.label(:assign_self_as_admin, "Assign me as occasion admin", class: "text-sm font-medium")
            p(class: "mt-1 text-xs text-stone-500") { "This grants administration for this occasion. It does not register you as a participant." }
          end
        end
        f.submit("Create occasion", class: BUTTON)
      end
    end
  end
end
