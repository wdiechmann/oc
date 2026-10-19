class Views::Invitations::Inbox < Views::Base
  def initialize(invitations:, **options)
    super(**options)
    @invitations = invitations
  end

  def view_template
    p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "Build together" }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Your invitations" }
    p(class: "mt-4 max-w-2xl text-stone-600") { "These invitations match your verified sign-in email. Each card identifies the tenant or occasion you will administer." }
    if @invitations.empty?
      p(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8 text-stone-500") { "No pending invitations for this email. If you expected one, sign in using the address that was invited." }
    else
      div(class: "mt-8 grid gap-6 md:grid-cols-2") do
        @invitations.each do |invitation|
          section(class: "rounded-2xl border border-stone-200 bg-white p-8") do
            h2(class: "text-2xl font-semibold") { invitation["occasion_name"] || invitation.fetch("tenant_name") }
            p(class: "mt-3 text-sm text-stone-600") { invitation["occasion_id"] ? "Role: Occasion administrator · #{invitation.fetch("tenant_name")}" : "Role: Tenant administrator" }
            if invitation["status"] == "accepted"
              p(class: "mt-2 text-xs text-stone-500") { "Accepted · your current occasion access is checked when you open it." }
            else
              p(class: "mt-2 text-xs text-stone-500") { "Invitation deadline: #{invitation.fetch('expires_at')}" }
            end
            if invitation["occasion_id"] && invitation["status"] == "accepted"
              a(href: tenant_occasion_path(invitation.fetch("tenant_id"), invitation.fetch("occasion_id")), class: "mt-6 inline-block font-semibold text-emerald-800 hover:underline") { "Open occasion" }
            else
              target = invitation["occasion_id"] ? accept_tenant_occasion_admin_invitation_path(invitation.fetch("tenant_id"), invitation.fetch("occasion_id"), invitation.fetch("invitation_id")) : accept_tenant_admin_invitation_path(invitation.fetch("tenant_id"), invitation.fetch("invitation_id"))
              form_with(url: target) do |f|
                f.submit(invitation["occasion_id"] ? "Accept occasion-admin invitation" : "Accept tenant-admin invitation", class: BUTTON)
              end
            end
          end
        end
      end
    end
  end
end
