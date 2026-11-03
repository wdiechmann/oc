require "csv"

class ChartCsv
  class Invalid < StandardError; end
  MAX_BYTES = 2_097_152
  def self.parse(upload)
    raise Invalid, "Choose a CSV file, up to 2 MiB." unless upload.respond_to?(:read)
    raw = upload.read(MAX_BYTES + 1)
    raise Invalid, "CSV files must be UTF-8 and at most 2 MiB." if raw.bytesize > MAX_BYTES
    raw = raw.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    raise Invalid, "CSV files must be UTF-8." unless raw.valid_encoding?
    # Regional spreadsheet exports commonly use semicolons or tabs.
    first_line = raw.each_line.find { |line| line.gsub(/[;,\t\s]/, "").present? }.to_s
    separator = [ ",", ";", "\t" ].max_by do |candidate|
      CSV.parse_line(first_line, col_sep: candidate)&.length || 0
    rescue CSV::MalformedCSVError
      0
    end
    rows = []
    CSV.parse(raw, col_sep: separator, liberal_parsing: false) do |row|
      next if row.all? { |value| value.to_s.strip.empty? }
      raise Invalid, "Use at most 500 rows and 32 columns." if rows.length > 500 || row.length > 32
      rows << row.map { |v| decode(v.to_s) }
    end
    headers = rows.shift || []
    unless headers.any? && headers.all? { |h| h.present? && h.bytesize <= 120 } && headers.uniq.length == headers.length && rows.any? && rows.all? { |row| row.length == headers.length }
      raise Invalid, "Use unique nonblank headers and 1–500 rows with matching columns."
    end
    { headers: headers, records: rows }
  rescue CSV::MalformedCSVError
    raise Invalid, "Check CSV quotes and delimiters. Use comma-, semicolon- or tab-separated UTF-8 CSV."
  end
  def self.generate(columns, rows)
    CSV.generate(force_quotes: true, row_sep: "\r\n") do |csv|
      csv << columns
      rows.each { |row| csv << row.map { |v| encode(v.to_s) } }
    end
  end
  def self.encode(value) = value.match?(/\A(?:'|[[:space:]]*[=+@-])/) ? "'#{value}" : value
  def self.decode(value) = value.start_with?("'") && encode(value.delete_prefix("'")) == value ? value.delete_prefix("'") : value
end
