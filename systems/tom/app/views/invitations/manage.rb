class Views::Invitations::Manage < Views::Base
  def initialize(tenant_id:, invitations:, key:, email: nil, **options)
    super(**options)
    @tenant_id, @invitations, @key, @email = tenant_id, invitations, key, email
  end

  def view_template
    a(href: tenant_path(@tenant_id), class: "text-sm font-medium text-emerald-800 hover:underline") { "← Tenant overview" }
    h1(class: "mt-8 text-4xl font-semibold tracking-tight") { "Share tenant administration" }
    p(class: "mt-4 max-w-2xl text-stone-600 leading-relaxed") { "Invite someone you trust to administer this entire tenant, including its occasions. Access begins only after they verify the invited email and accept." }
    section(class: "mt-8 max-w-2xl rounded-2xl border border-stone-200 bg-white p-8") do
      h2(class: "text-xl font-semibold") { "Invite a tenant admin" }
      form_with(url: tenant_admin_invitations_path(@tenant_id)) do |f|
        f.hidden_field(:idempotency_key, value: @key)
        div(class: "mt-5") do
          f.label(:email, "Their email address", class: "text-sm font-medium")
          f.email_field(:email, required: true, maxlength: 254, value: @email, autocomplete: "off", class: FIELD)
        end
        p(class: "mt-3 text-xs text-stone-500") { "Invitations expire after seven days and may be revoked before acceptance." }
        f.submit("Invite tenant admin", class: BUTTON)
      end
      p(class: "mt-4 text-xs text-stone-500") { "Development messages are saved privately in EP’s tmp/admin_invitations mailbox. Real email delivery is not configured." } if Rails.env.development?
    end
    section(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8") do
      h2(class: "text-xl font-semibold") { "Recent invitations" }
      if @invitations.empty?
        p(class: "mt-5 text-stone-500") { "No invitations yet." }
      else
        div(class: "mt-5 overflow-x-auto") do
          table(class: "w-full text-left text-sm") do
            thead do
              tr(class: "border-b border-stone-200 text-stone-500") { %w[Email Status Expiry Action].each { |title| th(class: "px-3 py-3 font-medium") { title } } }
            end
            tbody do
              @invitations.each do |invitation|
                tr(class: "border-b border-stone-100") do
                  td(class: "break-all px-3 py-4") { invitation.fetch("email") }
                  td(class: "px-3 py-4") { invitation.fetch("status").capitalize }
                  td(class: "px-3 py-4 whitespace-nowrap") { invitation.fetch("expires_at") }
                  td(class: "px-3 py-4") do
                    if invitation["status"] == "pending"
                      form_with(url: revoke_tenant_admin_invitation_path(@tenant_id, invitation.fetch("invitation_id"))) do |f|
                        f.submit("Revoke", class: "cursor-pointer font-semibold text-red-800 hover:underline")
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
      p(class: "mt-4 text-xs text-stone-500") { "Showing up to 100 recent invitations. Revoking an invitation does not remove an accepted administrator." }
    end
  end
end
