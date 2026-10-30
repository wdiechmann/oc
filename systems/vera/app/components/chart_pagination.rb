class Components::ChartPagination < Components::Base
  register_output_helper :will_paginate
  def initialize(data:, collection:, query: "")
    @data, @collection, @query = data, collection, query
  end
  def view_template
    div(id: "coa-pagination", class: "mt-5", data: { current_page: @collection.current_page.to_i, total_pages: @collection.total_pages }) do
      nav(aria_label: "Chart pages", class: "coa-pagination") do
        will_paginate(@collection, params: { q: @query.presence, append: nil, source_version: nil, focus_id: nil, focus_edge: nil }, previous_label: "← Previous", next_label: "Next →", inner_window: 1, outer_window: 1)
      end
      if @collection.next_page
        a(href: tenant_book_chart_path(@data.fetch("tenant_id"), @data.fetch("book_id"), page: @collection.next_page, q: @query.presence), data: { coa_next: true }, class: "mt-4 inline-block rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-medium text-teal-900") { "Load more rows" }
      end
    end
  end
end
