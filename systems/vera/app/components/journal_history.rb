class Components::JournalHistory < Components::Base
  def initialize(data:)
    @data = data
  end
  def view_template
    draft = @data.fetch("selected")
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Journal history · #{draft.dig('data', 'name')}" }
    history = (@data.fetch("drafts").find { |d| d["id"] == draft["id"] } || draft).fetch("history", [])
    p(class: "mt-4 text-sm text-stone-500") { "No revisions available yet." } if history.empty?
    history.reverse_each do |revision|
      div(class: "mt-4 border-t border-stone-200 pt-3 text-sm") do
        a(href: tenant_book_journals_path(@data["tenant_id"], @data["book_id"], draft_id: draft["id"], version: revision["version"]), class: "font-medium text-teal-900 underline") { "Revision #{revision['version']}" }
        p(class: "mt-1 text-xs text-stone-500") { "#{revision['accepted_at']} · Actor #{revision['actor_identity_id']} · Application #{revision['application_id']}" }
      end
    end
  end
end
