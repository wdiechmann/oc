require "test_helper"

class EnclosureScanTest < ActiveSupport::TestCase
  class FakeScan < EnclosureScan
    attr_reader :directory, :commands
    def initialize(text:, pdf_text: nil, fail: false)
      @text, @pdf_text, @fail, @commands = text, pdf_text, fail, []
    end
    private
    def run(dir, *args)
      @directory = dir
      @commands << args
      raise Errno::ENOENT if @fail
      return @pdf_text.to_s if args.first == "pdftotext"
      return "eng\nosd\n" if args.include?("--list-langs")
      if args.first == "pdftoppm"
        File.write(File.join(dir, "page-1.png"), "synthetic")
        return ""
      end
      @text
    end
  end
  def file(type) = { "content_type"=>type, "content"=>Base64.strict_encode64("synthetic private document") }
  test "text PDFs skip OCR and temporary files are removed" do
    scan = FakeScan.new(text: "", pdf_text: "Supplier: Example Trading Limited\nTotal 125,00 DKK")
    result = scan.call(file("application/pdf"))
    assert_equal "pdf_text", result["method"]
    assert_equal 12500, result["fields"].find { |f| f["key"] == "total" }["value"]
    assert_equal [ "pdftotext" ], scan.commands.map(&:first)
    refute Dir.exist?(scan.directory)
  end
  test "scanned PDFs render bounded pages and OCR only installed languages" do
    scan = FakeScan.new(text: "Supplier: Example Limited\nVAT 25% 25,00\nTotal 125,00")
    result = scan.call(file("application/pdf"))
    assert_equal "ready", result["status"]
    assert_equal "ocr", result["method"]
    renderer = scan.commands.find { |args| args.first == "pdftoppm" }
    assert_includes renderer, "2000"
    ocr = scan.commands.last
    assert_equal "eng", ocr[ocr.index("-l") + 1]
    refute Dir.exist?(scan.directory)
  end
  test "missing tools do not prevent attaching and clean up temporary content" do
    scan = FakeScan.new(text: "", fail: true)
    assert_equal "unavailable", scan.call(file("image/png"))["status"]
    refute Dir.exist?(scan.directory)
    assert_equal 2, EnclosureScan::SLOTS.size
  end
  test "a busy scanner returns promptly without consuming another slot" do
    tokens = 2.times.map { EnclosureScan::SLOTS.pop }
    assert_equal "busy", EnclosureScan.call(file("image/png"))["status"]
  ensure
    tokens.each { |token| EnclosureScan::SLOTS << token }
  end
end
