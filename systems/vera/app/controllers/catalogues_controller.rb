class CataloguesController < FinanceSetupController
  private
  def destination(_result = nil) = tenant_book_catalogues_path(params[:tenant_id], params[:book_id])
  def execute_command(action, attrs, key) = ep.catalogue_command(params[:tenant_id], params[:book_id], action.delete_prefix("catalogue_"), attrs, key)
  def attributes_for(action, entry_id)
    attrs = { expected_version: Integer(params[:expected_version], exception: false) }
    return attrs if action == "catalogue_initialize"
    attrs.merge!(code: params[:code].to_s, name: params[:name].to_s)
    if action == "catalogue_create"
      attrs[:kind] = params[:kind].to_s
    else
      attrs.merge!(entry_id: entry_id, active: params[:active] == "true", expected_entry_version: Integer(params[:expected_entry_version], exception: false))
    end
    attrs
  end
  def show_setup(status: 200, message: nil)
    data = ep.catalogues(params[:tenant_id], params[:book_id])
    options = { data: data, token: method(:form_token), draft: @attrs && { action: @action, attrs: @attrs }, message: message, check_url: completion_url, retry_url: retry_url }
    if request.format.turbo_stream?
      render Components::CataloguesStream.new(**options), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Catalogues::Show.new(**options, signed_in: signed_in?, notice: flash[:notice]), status: status
    end
  end
  def error_message(code)
    case code
    when "version_conflict" then "A newer catalogue/setup revision exists. Compare your preserved draft with the accepted entry before reapplying."
    when "code_taken" then "That code is already reserved in this book’s catalogue. Choose another code."
    when "catalogues_initialized" then "This book’s catalogues have already been initialized. Refresh to see them."
    when "catalogue_not_initialized" then "Initialize this book’s catalogues before adding entries."
    when "invalid_catalogue" then "Check the code and name. Codes use 1–40 letters, digits, dots, underscores or hyphens."
    else super
    end
  end
end
