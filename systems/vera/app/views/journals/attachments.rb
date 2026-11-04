class Views::Journals::Attachments < Views::Base
  def initialize(data:, info:, upload:, token:, **options)
    super(**options)
    @data, @info, @upload, @token = data, info, upload, token
  end
  def view_template
    a(href: tenant_book_journals_path(@data["tenant_id"], @data["book_id"], draft_id: @info["draft_id"]), class: "text-teal-900 underline") { "← Journal" }
    render Components::JournalAttachments.new(data: @data, info: @info, upload: @upload, token: @token)
  end
end
