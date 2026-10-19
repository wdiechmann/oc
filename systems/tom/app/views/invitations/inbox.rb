class Views::Invitations::Inbox < Views::Base
  def initialize(invitations:, **options)
    super(**options)
    @invitations = invitations
  end

  def view_template
    p(class: "text-xs font-bold uppercase tracking-widest text-emerald-800") { "Build together" }
    h1(class: "mt-4 text-4xl font-semibold tracking-tight") { "Your invitations" }
    p(class: "mt-4 max-w-2xl text-stone-600") { "These invitations match your verified sign-in email. Accept only if you want to become an administrator for the entire tenant." }
    if @invitations.empty?
      p(class: "mt-8 rounded-2xl border border-stone-200 bg-white p-8 text-stone-500") { "No pending invitations for this email. If you expected one, sign in using the address that was invited." }
    else
      div(class: "mt-8 grid gap-6 md:grid-cols-2") do
        @invitations.each do |invitation|
          section(class: "rounded-2xl border border-stone-200 bg-white p-8") do
            h2(class: "text-2xl font-semibold") { invitation.fetch("tenant_name") }
            p(class: "mt-3 text-sm text-stone-600") { "Role: Tenant administrator" }
            p(class: "mt-2 text-xs text-stone-500") { "Expires: #{invitation.fetch('expires_at')}" }
            form_with(url: accept_tenant_admin_invitation_path(invitation.fetch("tenant_id"), invitation.fetch("invitation_id"))) do |f|
              f.submit("Accept tenant-admin invitation", class: BUTTON)
            end
          end
        end
      end
    end
  end
end
