class BooksController < ApplicationController
  before_action :require_session
  rescue_from Ep::Client::Error, with: :book_error
  def index
    page Views::Books::Index, data: ep.books(params[:tenant_id])
  end
  def new
    data = ep.books(params[:tenant_id])
    prepare_key
    page Views::Books::New, data: data, key: session[:book_form_key]
  end
  def show
    detail = ep.book(params[:tenant_id], params[:id])
    data = ep.books(params[:tenant_id])
    prepare_key
    page Views::Books::Show, data: data, detail: detail, key: session[:book_form_key]
  end
  def edit_dialog
    detail = ep.book(params[:tenant_id], params[:id])
    data = ep.books(params[:tenant_id])
    if detail["status"] != "ready" || !detail["book"] || session[:book_operation]
      content = Components::SharedDialogFeedback.new(message: "Refresh the book after its view catches up and resolve any pending save before editing.", check_url: session[:book_operation] && completion_tenant_books_path(params[:tenant_id]))
      return render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html", status: :conflict
    end
    prepare_key
    content = Components::BookDetailsDialog.new(tenant_id: params[:tenant_id], books: data.fetch("books"), book: detail.fetch("book"), key: session[:book_form_key])
    render Components::SharedDialogStream.new(content: content), content_type: "text/vnd.turbo-stream.html"
  end
  def create
    return unless valid_form?
    operation("FinanceBookCreate")
    attributes = { name: params[:name].to_s, code: params[:code].to_s, base_currency: params[:base_currency].to_s, accounting_authority: params[:accounting_authority].to_s, timezone: params[:timezone].to_s, fiscal_year_start_month: Integer(params[:fiscal_year_start_month], exception: false), parent_book_id: params[:parent_book_id].presence }
    accepted(ep.create_book(params[:tenant_id], attributes, session[:book_form_key]))
  end
  def update
    return unless valid_form?
    operation("FinanceBookRevise")
    attributes = { name: params[:name].to_s, parent_book_id: params[:parent_book_id].presence, expected_version: Integer(params[:expected_version], exception: false) }
    accepted(ep.revise_book(params[:tenant_id], params[:id], attributes, session[:book_form_key]))
  end
  def completion
    op = session[:book_operation]
    return unavailable_view("No book request is available to check.", 404) unless op && op["tenant_id"] == params[:tenant_id]
    result = ep.book_receipt(op.fetch("type"), op.fetch("key"))
    if result["status"] == "accepted"
      session.delete(:book_operation)
      session.delete(:book_form_key)
      redirect_to tenant_book_path(params[:tenant_id], result.fetch("result").fetch("book_id")), notice: "EP confirms the book request was accepted.", status: :see_other
    else
      book_feedback("No accepted receipt is visible yet. The outcome is still unknown; do not assume failure or repeat the save.", 200)
    end
  end
  private
  def require_session
    return if signed_in?
    reset_session
    if request.format.turbo_stream?
      unavailable_view("Your sign-in has expired. Sign in again before continuing.", 401)
    else
      redirect_to new_session_path, status: :see_other
    end
  end
  def scope = "#{params[:tenant_id]}/#{params[:id] || 'new'}"
  def prepare_key
    if session[:book_form_scope] != scope || session[:book_form_key].blank?
      session[:book_form_scope], session[:book_form_key] = scope, SecureRandom.uuid
    end
  end
  def valid_form?
    key = session[:book_form_key]
    valid = session[:book_form_scope] == scope && key.present? && ActiveSupport::SecurityUtils.secure_compare(key, params[:idempotency_key].to_s)
    book_feedback("Refresh this book form before saving.", 422) unless valid
    valid
  end
  def operation(type)
    session[:book_operation] = { "tenant_id"=>params[:tenant_id], "type"=>type, "key"=>session[:book_form_key] }
  end
  def accepted(result)
    session.delete(:book_form_key)
    session.delete(:book_operation)
    redirect_to tenant_book_path(params[:tenant_id], result.fetch("book_id")), notice: "Book setup accepted at revision #{result['stream_version']}. Its query view may still be updating.", status: :see_other
  end
  def book_error(error)
    return unavailable if error.status >= 500
    if [ 401, 403, 404 ].include?(error.status)
      reset_session if error.status == 401
      return unavailable_view("Books are not available for your current access.", error.status)
    end
    session.delete(:book_operation) unless error.code == "idempotency_conflict"
    message = case error.code
    when "version_conflict" then "A newer revision exists. Your input is still in this form; copy it before refreshing to compare and reapply your changes."
    when "hierarchy_cycle" then "That parent would create a cycle in the book hierarchy. Choose another parent."
    when "code_taken" then "That book code is already in use in this tenant. Choose another code."
    when "invalid_parent" then "Choose an available parent in this tenant."
    when "idempotency_conflict" then "This request key already belongs to another save. Check completion before starting a new request."
    else "Check the book fields and try again."
    end
    book_feedback(message, error.status)
  end
  def feedback(message, status:)
    book_feedback(message, status)
  end
  def unavailable
    return unavailable_view("The book view is unavailable or stopped. Its previous contents cannot be treated as current.", 503) if request.get? || request.head?
    book_feedback("EP is temporarily unavailable. Your save may already have been recorded; check completion before submitting again.", 503)
  end
  def book_feedback(message, status)
    link = session[:book_operation] && completion_tenant_books_path(params[:tenant_id])
    if request.format.turbo_stream?
      render Components::FeedbackStream.new(message: message, check_url: link), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Books::Unavailable.new(message: message, check_url: link, signed_in: signed_in?), status: status
    end
  end
  def unavailable_view(message, status)
    if request.format.turbo_stream?
      render Components::BooksUnavailableStream.new(message: message), content_type: "text/vnd.turbo-stream.html", status: status
    else
      render Views::Books::Unavailable.new(message: message, signed_in: signed_in?), status: status
    end
  end
end
