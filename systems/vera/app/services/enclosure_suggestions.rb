class EnclosureSuggestions
  MONEY = /(?<![\d.,])[-−]?\d(?:[\d., \u00a0]*\d)?(?![\d.,])/
  DATE = /\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}[.\/-]\d{1,2}[.\/-]\d{4})\b/
  def self.call(text)
    new(text).call
  end
  def initialize(text)
    @lines = text.lines.map { |line| line.strip.gsub(/[ \t]+/, " ") }.reject(&:empty?)
    @fields = []
  end
  def call
    amounts("total", "Total", /\b(?:grand total|amount due|total(?: incl\.? (?:vat|tax))?|i alt|at betale|til betaling|beløb til betaling)\b/i, exclude: /\b(?:netto|net |subtotal|excl|ekskl|moms i alt|total (?:moms|vat|tax)|(?:moms|vat|tax) total)\b/i)
    amounts("vat", "VAT", /\b(?:moms(?:beløb)?|vat(?: amount)?|tax amount)\b/i, exclude: /\b(?:inkl|incl|cvr|vat (?:id|no|number)|momsnr)\b/i)
    amounts("net", "Net amount", /\b(?:subtotal|sub total|net total|net amount|netto|ekskl\.? moms|excl\.? vat)\b/i)
    dates("date", "Invoice date", /\b(?:invoice date|fakturadato|udstedelsesdato|dato|date)\b/i, exclude: /\b(?:due|forfald|levering|delivery)\b/i)
    dates("due_date", "Due date", /\b(?:due date|forfaldsdato|forfald)\b/i)
    labelled("supplier", "Supplier", /\b(?:supplier|leverandør|seller|sælger)\s*[:：]\s*(.+)/i)
    labelled("invoice_number", "Invoice number", /\b(?:invoice\s*(?:no\.?|number|#)|faktura\s*(?:nr\.?|nummer|#))\s*[:：#]?\s*([\p{L}\d][\p{L}\d\/.\-]{0,59})/i)
    labelled("vat_number", "CVR / VAT number", /\b(?:cvr(?:-?nr\.?)?|vat\s*(?:id|no\.?|number))\s*[:：]?\s*((?:[A-Z]{2}\s*)?\d[\d .-]{5,18}\d)/i)
    currency = @lines.filter_map { |line| code = line[/\b(?:DKK|EUR|USD|GBP|SEK|NOK)\b/i]; [ code.upcase, line ] if code }.uniq { |value, _| value }
    add_candidates("currency", "Currency", currency)
    unless @fields.any? { |field| field["key"] == "supplier" }
      possible = @lines.first(3).find { |line| line.match?(/[[:alpha:]]{3}/) && !line.match?(/\b(?:invoice|faktura|kvittering|receipt|dato|date|total|moms|vat)\b/i) && line.length <= 100 }
      add("supplier", "Possible supplier", possible, possible) if possible
    end
    @fields
  end
  private
  def amounts(key, label, pattern, exclude: nil)
    candidates = @lines.filter_map do |line|
      next unless line.match?(pattern) && !(exclude && line.match?(exclude))
      # Ignore percentages: a rate alone is not a VAT amount.
      tail = line.sub(/.*?#{pattern.source}/i, "").gsub(/\d+(?:[.,]\d+)?\s*%/, "")
      raw = tail.scan(MONEY).last
      minor = money(raw)
      [ minor, line ] unless minor.nil?
    end
    add_candidates(key, label, candidates.uniq { |value, _| value }, amount: true)
  end
  def money(raw)
    return if raw.nil?
    value = raw.delete(" \u00a0").tr("−", "-")
    negative = value.start_with?("-")
    value = value.delete_prefix("-")
    if value.match?(/[.,]\d{2}\z/)
      whole, fraction = value[0...-3], value[-2..]
      return unless whole.match?(/\A\d+(?:[.,]\d{3})*\z/)
      minor = whole.delete(".,").to_i * 100 + fraction.to_i
    elsif value.match?(/\A\d+\z/)
      minor = value.to_i * 100
    else
      return
    end
    return if minor > 9_000_000_000_000
    negative ? -minor : minor
  end
  def dates(key, label, pattern, exclude: nil)
    candidates = @lines.filter_map do |line|
      next unless line.match?(pattern) && !(exclude && line.match?(exclude))
      raw = line[DATE]
      next unless raw
      date = raw.match?(/\A\d{4}-/) ? Date.iso8601(raw) : Date.strptime(raw.tr("/-", "."), "%d.%m.%Y")
      [ date.iso8601, line ]
    rescue Date::Error
      nil
    end
    add_candidates(key, label, candidates.uniq { |value, _| value })
  end
  def labelled(key, label, pattern)
    candidates = @lines.filter_map { |line| match = line.match(pattern); [ match[1].strip, line ] if match }.uniq { |value, _| value }
    add_candidates(key, label, candidates)
  end
  def add_candidates(key, label, candidates, amount: false)
    candidates.first(3).each do |value, source|
      add(key, candidates.length > 1 ? "#{label} candidate" : label, value, source, amount: amount)
    end
  end
  def add(key, label, value, source, amount: false)
    @fields << { "key"=>key, "label"=>label, "value"=>value, "source"=>source, "amount"=>amount }
  end
end
