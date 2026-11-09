class Components::JournalAttachments < Components::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::TurboFrameTag
  FIELD = Views::Base::FIELD
  BUTTON = Views::Base::BUTTON
  def initialize(data:, info:, upload:, token:, message: nil, check_url: nil, retry_url: nil)
    @message, @check, @retry = message, check_url, retry_url
    @data, @info, @upload, @token = data, info, upload, token
    @tid, @bid = data["tenant_id"], data["book_id"]
  end
  def view_template
    p(class: "mt-5 text-xs font-semibold uppercase tracking-wide text-teal-800") { "#{@data['book_name']} · #{@data.dig('selected', 'data', 'name')}" }
    h2(id: "shared-dialog-title", class: "mt-6 text-2xl font-semibold") { "Enclosures · Posting #{@info['posting_id']}" }
    p(role: "status", class: "mt-3 text-sm text-amber-900") { @message } if @message
    if @check
      a(href: @check, data: { turbo_stream: true }, class: "mt-3 block underline") { "Check completion" }
      form_with(url: @retry, method: :post) { |f| f.submit("Retry original request", class: BUTTON) } if @retry
    end
    @info.fetch("attachments").each do |file|
      div(class: "mt-4 min-w-0 break-words rounded-lg border bg-white p-4") do
        a(href: download_attachment_tenant_book_journals_path(@tid, @bid, attachment_id: file["id"]), data: { turbo: false }, class: "text-teal-900 underline") { file["filename"] }
        p(class: "mt-2 break-all text-xs text-stone-500") { "#{file['byte_size']} bytes · SHA-256 #{file['sha256']}" }
        details(class: "mt-3") do
          summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Preview document" }
          document_preview(preview_attachment_tenant_book_journals_path(@tid, @bid, attachment_id: file["id"]), file["content_type"], file["filename"], attachment_id: file["id"])
        end
        interpretation_preview(file)
      end
    end
    if !@check && @data.dig("permissions", "prepare") && @data["status"] == "ready"
      if @upload
        p(class: "mt-6 text-sm") { "Attach #{@upload['filename']} (#{@upload['byte_size']} bytes) to posting #{@info['posting_id']}?" }
        document_preview(preview_attachment_tenant_book_journals_path(@tid, @bid, row_id: @info["row_id"], upload_id: @upload["upload_id"]), @upload["content_type"], @upload["filename"], row_id: @info["row_id"], upload_id: @upload["upload_id"])
        form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, id: "attach-enclosure") do |f|
          f.hidden_field(:form_token, value: @token.call("journal_attachment", @info["draft_id"], @info["row_id"], @upload))
          f.hidden_field(:draft_id, value: @info["draft_id"])
          f.hidden_field(:expected_draft_version, value: @data.dig("selected", "version"))
          f.hidden_field(:expected_version, value: @data["latest_version"])
          @data.fetch("contexts").each { |k, v| input(type: "hidden", name: "contexts[#{k}]", value: v) }
          f.submit("Attach enclosure", class: BUTTON)
        end
      else
        form_with(url: upload_attachment_tenant_book_journals_path(@tid, @bid), method: :post, multipart: true, class: "mt-6") do |f|
          f.hidden_field(:row_id, value: @info["row_id"])
          f.label(:file, "PDF, PNG or JPEG enclosure (up to 5 MiB)")
          f.file_field(:file, accept: ".pdf,.png,.jpg,.jpeg", required: true, class: FIELD)
          f.submit("Review enclosure", class: BUTTON)
        end
      end
    end
  end
  def interpretation_preview(file)
    record = @info.fetch("interpretations", []).find { |entry| entry["attachment_id"] == file["id"] }
    return unless record
    guess = record.fetch("best_guess")
    row = guess.fetch("row")
    details(class: "mt-3") do
      summary(class: "cursor-pointer text-sm font-medium text-teal-900") { "Account and amount suggestion" }
      p(class: "mt-2 text-xs text-stone-500") { guess["source"] == "confirmed_supplier_rows" ? "Based on explicitly saved choices for this supplier in this book." : "Based on the document and current chart. Review the choices before using them." }
      p(class: "mt-2 text-sm text-amber-900") { "Document currency differs from this book; enter converted amounts explicitly." } if guess["currency_mismatch"]
      dl(class: "mt-3 grid gap-3 sm:grid-cols-2") do
        %w[debit credit].each do |side|
          account = @data.fetch("accounts").find { |entry| entry["id"] == row["#{side}_account_id"] }
          div do
            dt(class: "text-xs text-stone-500") { "#{side.capitalize} account" }
            dd { account ? "#{account['number']} · #{account['name']}" : "Choose an account" }
          end
          amount = row[side == "debit" ? "amount_minor" : "credit_amount_minor"]
          div do
            dt(class: "text-xs text-stone-500") { "#{side.capitalize} amount" }
            dd { amount.nil? ? "Not determined" : JournalMoney.format(amount, separator: @data.fetch("decimal_separator", ".")) }
          end
        end
      end
      p(class: "mt-2 text-xs text-stone-500") { "This recalculated suggestion does not change the saved row." }
    end
  end
  def document_preview(url, type, filename, **query)
    div(class: "enclosure-preview mt-3", data: { enclosure_preview: true }) do
      div(class: "enclosure-document") do
        if type == "application/pdf"
          iframe(src: url, title: "Preview of #{filename}", loading: "lazy", class: "rounded border border-stone-200")
        elsif %w[image/png image/jpeg].include?(type)
          img(src: url, alt: "Preview of #{filename}", loading: "lazy", class: "rounded")
        end
        a(href: url, target: "_blank", rel: "noopener", data: { turbo: false }, class: "mt-2 inline-block text-sm text-teal-900 underline") { "Open document" }
      end
      turbo_frame_tag("enclosure-scan-#{query[:upload_id] || query[:attachment_id]}", src: scan_attachment_tenant_book_journals_path(@tid, @bid, **query), loading: "lazy", class: "enclosure-suggestions") do
        p(role: "status", class: "text-sm text-stone-500") { "Scanning document for suggested values…" }
      end
    end
  end
end
