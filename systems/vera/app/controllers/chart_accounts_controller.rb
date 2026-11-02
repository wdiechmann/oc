require "will_paginate/collection"

class ChartAccountsController < FinanceSetupController
  private

  def destination(result = nil)
    id = @attrs && @attrs[:account_id]
    id ||= result&.dig("event_ids", 0) if @action == "account_create"
    tenant_book_chart_path(params[:tenant_id], params[:book_id], focus_id: id)
  end

  def attributes_for(action, account_id)
    attrs = super
    attrs[:number] = nil unless params[:kind] == "posting"
    attrs.merge!(position: Integer(params[:position], exception: false), formula: params[:formula].presence)
    if params.key?(:vat_entry_id) || params.key?(:category_entry_id)
      attrs.merge!(vat_entry_id: params[:vat_entry_id].presence, category_entry_id: params[:category_entry_id].presence)
    else
      attrs.merge!(vat_code: params[:vat_code].presence, category: params[:category].presence)
    end
    attrs
  end

  def show_setup(status: 200, message: nil)
    query = params.permit(:page, :q, :source_version, :focus_id).to_h
    if @attrs
      query.delete("source_version")
      query.delete("q")
      query["focus_id"] = @attrs[:account_id] if @attrs[:account_id]
    end
    data = ep.chart_accounts(params[:tenant_id], params[:book_id], query)
    pagination = data.fetch("pagination")
    collection = WillPaginate::Collection.create(pagination.fetch("page"), pagination.fetch("per_page"), pagination.fetch("total_entries")) { |pager| pager.replace(data.fetch("accounts")) }
    options = { data: data, collection: collection, token: method(:form_token), draft: @attrs && { action: @action, attrs: @attrs }, message: message, check_url: completion_url, retry_url: retry_url, query: query["q"].to_s, focus_id: query["focus_id"], focus_edge: params[:focus_edge].to_s }
    if request.format.turbo_stream?
      if request.get? && params[:append] == "1"
        render Components::ChartPageStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
      else
        render Components::ChartStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
      end
    else
      render Views::ChartAccounts::Show.new(**options, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
  end

  def error_message(code)
    case code
    when "invalid_catalogue_reference" then "Choose a VAT/category entry belonging to this book and the correct catalogue."
    when "inactive_catalogue_entry" then "That catalogue entry is inactive. Keep an existing association or choose an active entry."
    when "catalogue_not_initialized" then "Initialize this book’s VAT/category catalogues before assigning catalogue entries."
    else super
    end
  end

  def setup_error(error)
    if error.code == "chart_changed"
      return feedback("The chart changed while loading more rows. Refresh the chart before continuing; your current draft is still in the editor.", status: 409)
    end
    super
  end
end
