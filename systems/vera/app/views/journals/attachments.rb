class Views::Journals::Attachments < Views::Base
  def initialize(data:, info:, upload:, token:, **options)
    super(**options)
    @data, @info, @upload, @token = data, info, upload, token
    @tid, @bid = data["tenant_id"], data["book_id"]
  end
  def view_template
    a(href: tenant_book_journals_path(@tid, @bid, draft_id: @info["draft_id"]), class: "text-teal-900 underline") { "← Journal" }
    p(class: "mt-5 text-xs font-semibold uppercase tracking-wide text-teal-800") { "#{@data['book_name']} · #{@data.dig('selected', 'data', 'name')}" }
    h1(class: "mt-6 text-2xl font-semibold") { "Enclosures · Posting #{@info['posting_id']}" }
    @info.fetch("attachments").each do |file|
      div(class: "mt-4 min-w-0 break-words rounded-lg border bg-white p-4") do
        a(href: download_attachment_tenant_book_journals_path(@tid, @bid, attachment_id: file["id"]), data: { turbo: false }, class: "text-teal-900 underline") { file["filename"] }
        p(class: "mt-2 break-all text-xs text-stone-500") { "#{file['byte_size']} bytes · SHA-256 #{file['sha256']}" }
      end
    end
    if @data.dig("permissions", "prepare") && @data["status"] == "ready"
      if @upload
        p(class: "mt-6 text-sm") { "Attach #{@upload['filename']} (#{@upload['byte_size']} bytes) to posting #{@info['posting_id']}?" }
        form_with(url: tenant_book_journals_path(@tid, @bid), method: :patch, data: { turbo: false }, id: "attach-enclosure") do |f|
          f.hidden_field(:form_token, value: @token.call("journal_attachment", @info["draft_id"], @info["row_id"], @upload))
          f.hidden_field(:draft_id, value: @info["draft_id"])
          f.hidden_field(:expected_draft_version, value: @data.dig("selected", "version"))
          f.hidden_field(:expected_version, value: @data["latest_version"])
          @data.fetch("contexts").each { |k, v| input(type: "hidden", name: "contexts[#{k}]", value: v) }
          f.submit("Attach enclosure", class: BUTTON)
        end
      else
        form_with(url: upload_attachment_tenant_book_journals_path(@tid, @bid), method: :post, multipart: true, data: { turbo: false }, class: "mt-6") do |f|
          f.hidden_field(:row_id, value: @info["row_id"])
          f.label(:file, "PDF, PNG or JPEG enclosure (up to 5 MiB)")
          f.file_field(:file, accept: ".pdf,.png,.jpg,.jpeg", required: true, class: FIELD)
          f.submit("Review enclosure", class: BUTTON)
        end
      end
    end
  end
end
