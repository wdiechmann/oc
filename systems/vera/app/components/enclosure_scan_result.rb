class Components::EnclosureScanResult < Components::Base
  register_element :turbo_frame
  def initialize(frame_id:, result:, separator:, retry_url:)
    @frame_id, @result, @separator, @retry = frame_id, result, separator, retry_url
  end
  def view_template
    turbo_frame(id: @frame_id, class: "enclosure-suggestions") do
      input(type: "hidden", name: "extraction_id", value: @result["extraction_id"], form: "attach-enclosure") if @result["extraction_id"]
      h3(class: "font-semibold") { "Suggested document values" }
      p(class: "mt-2 text-xs text-stone-500") { "Attaching will suggest accounts and amounts for an empty row. Review them before saving." } if @result["extraction_id"]
      if @result["status"] == "ready"
        p(class: "mt-2 text-xs text-stone-500") { "Review suggestions against the document before using them. Dates use day/month/year when not in ISO format." }
        p(class: "mt-1 text-xs text-stone-500") { "First 3 PDF pages inspected." } if @result["limited_pages"]
        p(class: "mt-3 text-sm") { "No labelled values recognized. Check the extracted text below." } if @result["fields"].empty?
        dl(class: "mt-3 grid gap-3 break-words sm:grid-cols-2") do
          @result["fields"].each do |field|
            div do
              dt(class: "text-xs text-stone-500") { field["label"] }
              dd(class: "font-medium tabular-nums") { field["amount"] ? JournalMoney.format(field["value"], separator: @separator) : field["value"] }
              p(class: "mt-1 text-xs text-stone-500") { field["source"] }
            end
          end
        end
        details(class: "mt-4") do
          summary(class: "cursor-pointer text-sm text-teal-900") { "Extracted text" }
          pre(class: "mt-2 whitespace-pre-wrap break-words rounded bg-stone-100 p-3 text-xs") { @result["text"] }
        end
      else
        p(role: "status", class: "mt-3 text-sm text-stone-600") do
          plain({ "busy"=>"The document scanner is busy. Try again shortly.", "no_text"=>"No readable text found. Try a clearer document.", "unavailable"=>"Document scanning is unavailable. The preview and attachment controls still work." }.fetch(@result["status"], "Document scanning is unavailable."))
        end
      end
      a(href: @retry, data: { turbo_frame: @frame_id }, class: "mt-3 inline-block text-sm text-teal-900 underline") { "Scan again" }
    end
  end
end
