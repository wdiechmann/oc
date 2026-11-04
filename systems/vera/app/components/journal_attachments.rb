class Components::JournalAttachments < Components::Base
  include Phlex::Rails::Helpers::FormWith
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
      end
    end
    if !@check && @data.dig("permissions", "prepare") && @data["status"] == "ready"
      if @upload
        p(class: "mt-6 text-sm") { "Attach #{@upload['filename']} (#{@upload['byte_size']} bytes) to posting #{@info['posting_id']}?" }
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
end
