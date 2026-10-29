class Views::Home::Index < Views::Base
  def view_template
    p(class: "text-xs font-semibold uppercase tracking-widest text-teal-800") { "Financial control" }
    h1(class: "mt-4 max-w-3xl text-4xl font-semibold tracking-tight sm:text-6xl") { "A clear view of every book." }
    p(class: "mt-6 max-w-2xl text-lg leading-relaxed text-stone-600") do
      plain "VERA brings financial control, accounting and settlement into one workspace, from individual occasion books to consolidated reporting."
    end
    section(class: "mt-10 rounded-2xl border border-teal-200 bg-teal-50 px-6 py-5", aria_label: "Workspace setup") do
      h2(class: "font-semibold text-teal-950") { "Your financial workspace is taking shape" }
      p(class: "mt-2 text-sm leading-relaxed text-teal-900") { "Sign in with your existing identity to see your current tenants and occasions. Tenant administrators can create and nest draft books; financial actions are not available yet." }
    end
    section(class: "mt-10 grid gap-5 md:grid-cols-3", aria_label: "Planned capabilities") do
      capability("01", "Books and contexts", "Keep occasion books distinct and connect them through a shared hierarchy.")
      capability("02", "Accounts and journals", "Maintain a chart of accounts and follow each accepted posting to its source.")
      capability("03", "Settlement and reporting", "Reconcile open items and build consolidated views without counting them twice.")
    end
  end

  private

  def capability(number, title, description)
    article(class: "rounded-2xl border border-stone-200 bg-white p-6") do
      p(class: "text-xs font-medium text-stone-400") { number }
      h2(class: "mt-4 text-lg font-semibold") { title }
      p(class: "mt-3 text-sm leading-relaxed text-stone-600") { description }
      p(class: "mt-5 text-xs font-medium text-stone-500") { "Planned" }
    end
  end
end
