require "base64"
require "tmpdir"
require "timeout"

class EnclosureScan
  class Failed < StandardError; end
  SLOTS = SizedQueue.new(2).tap { |queue| 2.times { queue << true } }
  MAX_TEXT = 40_000
  def self.call(file)
    new.call(file)
  end
  def call(file)
    acquired = SLOTS.pop(true)
    @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 25
    result = Dir.mktmpdir("vera-scan-") do |dir|
      input = File.join(dir, "document")
      bytes = Base64.strict_decode64(file.fetch("content"))
      raise Failed unless bytes.bytesize.between?(1, 5_242_880)
      File.binwrite(input, bytes)
      text = ""
      method = "ocr"
      if file["content_type"] == "application/pdf"
        text = run(dir, "pdftotext", "-f", "1", "-l", "3", "-layout", "-nopgbrk", input, "-")
        method = "pdf_text"
      end
      if text.scan(/[[:alpha:]]/).length < 30
        languages = run(dir, "tesseract", "--list-langs").lines.map(&:strip)
        selected = ENV.fetch("VERA_OCR_LANGUAGES", "dan+eng").split("+") & languages
        selected = [ "eng" ] if selected.empty? && languages.include?("eng")
        raise Failed if selected.empty?
        images = [ input ]
        if file["content_type"] == "application/pdf"
          run(dir, "pdftoppm", "-f", "1", "-l", "3", "-scale-to", "2000", "-png", input, File.join(dir, "page"))
          images = Dir.glob(File.join(dir, "page-*.png")).sort.first(3)
        elsif !%w[image/png image/jpeg].include?(file["content_type"])
          raise Failed
        end
        text = images.map { |image| run(dir, "tesseract", image, "stdout", "-l", selected.join("+"), "--psm", "3") }.join("\n")
        method = "ocr"
      end
      text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\u0000")[0, MAX_TEXT]
      { "status"=>text.strip.empty? ? "no_text" : "ready", "method"=>method, "text"=>text, "fields"=>EnclosureSuggestions.call(text), "limited_pages"=>file["content_type"] == "application/pdf" }
    end
    result
  rescue ThreadError
    { "status"=>"busy", "fields"=>[] }
  rescue SystemCallError, Failed, Timeout::Error, ArgumentError, IOError
    { "status"=>"unavailable", "fields"=>[] }
  ensure
    SLOTS << acquired if acquired
  end
  private
  def run(dir, *args)
    remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Timeout::Error if remaining <= 0
    output = File.join(dir, "output")
    pid = Process.spawn({ "OMP_THREAD_LIMIT"=>"1" }, *args, out: output, err: File::NULL, pgroup: true)
    _, status = Timeout.timeout([ remaining, 12 ].min) { Process.waitpid2(pid) }
    pid = nil
    raise Failed unless status.success?
    File.open(output, "rb") { |io| io.read(MAX_TEXT * 4).to_s.force_encoding("UTF-8").scrub }
  ensure
    if pid
      begin
        Process.kill("KILL", -pid)
        Process.waitpid(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end
