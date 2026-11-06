class Components::VatRowRefreshStream < Components::Base
  register_element :turbo_stream
  register_element :vat_index_refresh
  def initialize(data:, entry_id:, as_of:, version:, refresh_url:, token:)
    @token = token
    @data, @id, @date, @version, @url = data, entry_id, as_of, version, refresh_url
  end
  def view_template
    if @data["status"] == "ready" && @data["source_version"].to_i >= @version
      entry = @data.fetch("vat_entries").find { |e| e["id"] == @id }
      turbo_stream(action: "replace", target: "vat-code-row-#{@id}") do
        template { render Components::VatCodeRow.new(data: @data, entry: entry, as_of: @date) if entry }
      end
      if entry
        turbo_stream(action: "replace", target: "vat-settings-pending-#{@id}") do
          template { render Views::VatRules::Detail.new(data: @data, selected_entry: @id, as_of: @date, token: @token) }
        end
      end
    else
      turbo_stream(action: "update", target: "vat-refresh-#{@id}") do
        template do
          vat_index_refresh(data: { url: @url }, class: "ml-2 text-xs text-stone-500", role: "status") { "Updating…" }
        end
      end
    end
  end
end
