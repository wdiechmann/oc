class JournalMoney
  def self.separator(language)
    language.to_s.split(/[,;]/).first.to_s.match?(/\Aen(?:-|\z)|-US\z/i) || language.blank? ? "." : ","
  end
  def self.parse(value, separator:, signed: false)
    text = value.to_s.strip
    return 0 if text.empty?
    negative = signed && text.start_with?("-", "−")
    text = text[1..] if negative
    match = /\A(\d{1,11})(?:#{Regexp.escape(separator)}(\d{1,2}))?\z/.match(text)
    return unless match
    minor = match[1].to_i * 100 + match[2].to_s.ljust(2, "0").to_i
    (negative ? -minor : minor) if minor <= 9_000_000_000_000
  end
  def self.format(minor, separator:)
    sign = minor.to_i < 0 ? "−" : ""
    whole, fraction = minor.to_i.abs.divmod(100)
    "#{sign}#{whole}#{separator}#{fraction.to_s.rjust(2, '0')}"
  end
end
