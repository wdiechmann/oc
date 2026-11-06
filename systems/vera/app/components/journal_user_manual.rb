class Components::JournalUserManual < Components::Base
  def initialize(separator:)
    @separator = separator
  end
  def view_template
    section(id: "journal-user-manual") do
      h2(id: "shared-dialog-title", class: "text-2xl font-semibold") { "User manual" }
      p(class: "mt-4 text-sm leading-relaxed text-stone-600") { "Type two or more characters to search anywhere in account numbers, names, VAT or categories; use ↑/↓ and Enter or click a result to choose. Home/End go to the first/last row; Page Up/Down go to the previous/next row. Arrow keys navigate account results while searching and keep normal behavior in other inputs. Enter saves the current row and creates the next numbered line; Escape returns to the line reference; Cancel in More discards edits. Amounts use #{@separator} as the decimal point, without thousands separators." }
      p(class: "mt-4 text-sm leading-relaxed text-stone-600") { "New lines are created immediately with an ID from the book sequence and can receive attachments before accounts or amounts are entered. IDs remain on voided rows. Authorization, verification and final posting follow in a later workflow." }
    end
  end
end
