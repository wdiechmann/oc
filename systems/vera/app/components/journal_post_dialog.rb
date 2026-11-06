class Components::JournalPostDialog < Components::Base
  include Phlex::Rails::Helpers::FormWith
  def initialize(plan:, token:, separator:)
    @plan, @token, @separator = plan, token, separator
  end
  def view_template
    h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "Post journal · #{@plan['name']}" }
    form_with(url: tenant_book_journals_path(@plan["tenant_id"], @plan["book_id"]), method: :patch, data: { turbo: false }) do |f|
      f.hidden_field(:form_token, value: @token)
      f.hidden_field(:draft_id, value: @plan["draft_id"])
      f.submit("Post", disabled: !@plan["can_post"] || @plan["errors"].any?, class: "mt-4 cursor-pointer rounded bg-teal-950 px-5 py-3 font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50")
    end
    p(class: "mt-3 text-sm text-stone-600") { "Post confirms your authorization and verification of this journal. Posted entries are permanent. #{@plan['posting_date']} · #{@plan['base_currency']}. Balances use debit as positive and credit as negative." }
    @plan["errors"].each { |error| p(role: "alert", class: "mt-2 text-sm text-amber-900") { error.tr("_", " ") } }
    div(class: "mt-4 overflow-x-auto") do
      table(class: "w-full text-sm", data: { journal_impact: true }) do
        thead do
          tr do
            th(scope: "col", class: "p-3 text-left") { "Account" }
            [ "Prepost", "Post", "Postpost" ].each { |label| th(scope: "col", class: "p-3 text-right") { label } }
          end
        end
        tbody do
          @plan["accounts"].each do |row|
            tr(class: "border-t border-stone-200", data: { account_id: row.dig("account", "id") }) do
              td(class: "p-3") { "#{row.dig('account', 'number')} · #{row.dig('account', 'name')}" }
              %w[prepost_minor post_minor postpost_minor].each { |key| td(class: "p-3 text-right tabular-nums whitespace-nowrap") { JournalMoney.format(row[key], separator: @separator) } }
            end
          end
        end
      end
    end
  end
end
