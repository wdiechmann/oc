class Views::Reports::Index < Views::Base
  def initialize(data:, message: nil, check_url: nil, retry_url: nil, **options)
    super(**options)
    @data, @message, @check, @retry = data, message, check_url, retry_url
    @tid, @bid = data.fetch("tenant_id"), data.fetch("book_id")
    @editable = data["status"] == "ready" && data.dig("permissions", "configure") && !check_url
  end

  def view_template
    div(id: "vera-book-content", class: "min-w-0 break-words") do
      p(class: "mt-6 text-xs font-semibold uppercase tracking-widest text-teal-800") { @data.fetch("book_name") }
      header(class: "mt-2 flex items-center justify-between gap-4") do
        h1(class: "min-w-0 text-3xl font-semibold") { "Reports" }
        render Components::ContextMenu.new(id: "reports-index-actions", label: "Reports actions") do
          a(href: tenant_book_chart_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "Back to chart of accounts" }
          if @editable
            a(href: tenant_book_new_report_path(@tid, @bid), role: "menuitem", class: "vera-menu-item") { "New report" }
          else
            button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "New report" }
          end
        end
      end
      render Components::Toast.new(message: @message, kind: "alert") if @message
      p(role: "status", class: "mt-4 text-sm text-amber-900") { "The report view is updating. Refresh before running or editing reports." } unless @data["status"] == "ready"
      if @check
        a(href: @check, class: BUTTON) { "Check completion" }
        form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
      end
      div(class: "mt-6 divide-y divide-stone-200 rounded-lg border border-stone-200 bg-white") do
        @data.fetch("reports").each do |report|
          div(class: "flex items-center justify-between gap-4 px-4 py-3", data: { report_id: report["id"] }) do
            a(href: tenant_book_run_report_path(@tid, @bid, report["id"]), class: "min-w-0 font-medium text-teal-900 underline") { report["name"] }
            render Components::ContextMenu.new(id: "report-actions-#{report['id']}", label: "Actions for #{report['name']}") do
              if @data["status"] == "ready" && !@check
                a(href: tenant_book_run_report_path(@tid, @bid, report["id"]), role: "menuitem", class: "vera-menu-item") { "Run" }
              else
                button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Run" }
              end
              if @editable
                a(href: tenant_book_edit_report_path(@tid, @bid, report["id"]), role: "menuitem", class: "vera-menu-item") { "Edit" }
              else
                button(type: "button", role: "menuitem", disabled: true, class: "vera-menu-item") { "Edit" }
              end
            end
          end
        end
        p(class: "px-4 py-6 text-sm text-stone-500") { "No reports defined." } if @data.fetch("reports").empty?
      end
    end
  end
end
