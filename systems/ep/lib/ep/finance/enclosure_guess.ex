defmodule Ep.Finance.EnclosureGuess do
  @moduledoc "Book-local, explainable draft proposals; never posts or authorizes amounts."
  import Ecto.Query
  alias Ep.Repo
  alias Ep.Finance.{Account, Book, CatalogueEntry, EnclosureLearningRecord}
  @version "enclosure-guess-v1"

  def calculate(record) do
    accounts =
      Repo.all(
        from a in Account,
          where:
            a.tenant_id == ^record.tenant_id and a.book_id == ^record.book_id and
              a.kind == "posting" and a.active and not a.retired,
          order_by: a.id
      )

    allowed = Map.new(accounts, &{&1.id, &1})

    categories =
      Repo.all(
        from c in CatalogueEntry, where: c.book_id == ^record.book_id and c.kind == "category"
      )
      |> Map.new(&{&1.id, String.downcase(&1.code <> " " <> &1.name)})

    fields = record.extracted_fields["fields"] || []
    supplier = supplier(fields)

    samples =
      if supplier == "",
        do: [],
        else:
          Repo.all(
            from(r in EnclosureLearningRecord,
              where:
                r.tenant_id == ^record.tenant_id and r.book_id == ^record.book_id and
                  r.supplier_key == ^supplier and not is_nil(r.used_confirmed_at),
              order_by: [desc: r.used_confirmed_at, asc: r.id],
              select: map(r, [:id, :row_id, :used_values, :extracted_fields]),
              limit: 200
            ),
            log: false
          )
          |> Enum.filter(
            &(supplier(&1.extracted_fields["fields"] || []) == supplier &&
                &1.used_values["void"] != true && is_integer(&1.used_values["amount_minor"]) &&
                &1.used_values["amount_minor"] > 0)
          )
          |> Enum.uniq_by(& &1.row_id)

    pairs =
      samples
      |> Enum.filter(
        &(Map.has_key?(allowed, &1.used_values["debit_account_id"]) &&
            Map.has_key?(allowed, &1.used_values["credit_account_id"]))
      )
      |> Enum.frequencies_by(fn sample ->
        pair = {sample.used_values["debit_account_id"], sample.used_values["credit_account_id"]}

        if is_integer(unique(sample.extracted_fields["fields"], "total")) &&
             unique(sample.extracted_fields["fields"], "total") < 0,
           do: {elem(pair, 1), elem(pair, 0)},
           else: pair
      end)
      |> Enum.sort_by(fn {pair, n} -> {-n, pair} end)

    learned =
      case pairs do
        [{pair, n}] when n > 0 -> pair
        [{pair, n}, {_, second} | _] when n > second -> pair
        _ -> nil
      end

    expense = Enum.filter(accounts, &expense?(&1, categories))

    bank =
      accounts
      |> Enum.filter(&Regex.match?(~r/\b(bank|cash|kasse|kontant)\b/ui, &1.name))
      |> only()

    debit =
      if learned,
        do: allowed[elem(learned, 0)],
        else: named(expense, record.extracted_text) || only(expense)

    credit = if learned, do: allowed[elem(learned, 1)], else: bank
    total = unique(fields, "total")
    net = unique(fields, "net")
    vat = unique(fields, "vat")
    book = Repo.get!(Book, record.book_id)

    currencies =
      fields |> Enum.filter(&(&1["key"] == "currency")) |> Enum.map(& &1["value"]) |> Enum.uniq()

    mismatch = currencies != [] && currencies != [book.base_currency]
    total = if is_integer(total), do: abs(total)
    vat = if is_integer(vat), do: abs(vat)

    net =
      cond do
        is_integer(net) -> abs(net)
        is_integer(total) && is_integer(vat) && vat <= total -> total - vat
        vat in [nil, 0] && is_integer(total) -> total
        true -> nil
      end

    # Income on the credit side takes a gross asset debit and a net result credit.
    income_credit = credit && (income?(credit, categories) || output_vat?(credit, record))
    amount = if income_credit, do: total, else: net
    counter = if income_credit, do: net, else: total
    refund = is_integer(unique(fields, "total")) && unique(fields, "total") < 0

    {debit, credit, amount, counter} =
      if refund, do: {credit, debit, counter, amount}, else: {debit, credit, amount, counter}

    reference =
      [unique(fields, "supplier"), unique(fields, "invoice_number")]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" · ")
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
      |> String.slice(0, 120)

    row = %{
      "reference" => reference,
      "debit_account_id" => debit && debit.id,
      "credit_account_id" => credit && credit.id,
      "amount_minor" => if(mismatch, do: nil, else: amount),
      "credit_amount_minor" => if(mismatch, do: nil, else: counter),
      "amount_basis" => "net",
      "basis_override" => true,
      "vat_enabled" => is_integer(vat) && vat > 0,
      "void" => false
    }

    %{
      "algorithm" => @version,
      "setup_version" =>
        (Repo.get(Ep.Finance.SetupState, record.book_id) || %{version: 0}).version,
      "account_versions" =>
        Map.new(Enum.reject([debit, credit], &is_nil/1), &{&1.id, &1.version}),
      "row" => row,
      "supplier_key" => supplier,
      "source" => if(learned, do: "confirmed_supplier_rows", else: "chart_candidates"),
      "sample_ids" => Enum.map(samples, & &1.id),
      "currency_mismatch" => mismatch,
      "needs_review" => true,
      "extracted_vat_minor" => vat
    }
  end

  def supplier(fields),
    do: normalize(unique(fields, "vat_number") || unique(fields, "supplier") || "")

  def unique(fields, key) do
    case fields |> Enum.filter(&(&1["key"] == key)) |> Enum.map(& &1["value"]) |> Enum.uniq() do
      [value] -> value
      _ -> nil
    end
  end

  defp normalize(value),
    do: value |> to_string() |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  defp output_vat?(%{vat_entry_id: nil}, _record), do: false

  defp output_vat?(account, record) do
    row = Repo.get!(Ep.Finance.JournalRow, record.row_id)

    date =
      Repo.get!(Ep.Finance.JournalDraft, row.draft_id).data["posting_date"]
      |> Date.from_iso8601!()

    Repo.exists?(
      from r in Ep.Finance.VatRule,
        where:
          r.book_id == ^record.book_id and r.vat_entry_id == ^account.vat_entry_id and r.active and
            r.direction == "output" and r.valid_from <= ^date and
            (is_nil(r.valid_until) or r.valid_until >= ^date)
    )
  end

  defp expense?(a, categories),
    do:
      Regex.match?(
        ~r/expense|cost|omkost|udgift/ui,
        categories[a.category_entry_id] || a.category || ""
      )

  defp income?(a, categories),
    do:
      Regex.match?(
        ~r/income|revenue|indtægt/ui,
        categories[a.category_entry_id] || a.category || ""
      )

  defp only([value]), do: value
  defp only(_), do: nil

  defp named(accounts, text) do
    words = MapSet.new(String.downcase(text) |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true))

    ranked =
      accounts
      |> Enum.map(fn a ->
        {a,
         a.name
         |> String.downcase()
         |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
         |> Enum.count(&(String.length(&1) >= 4 && MapSet.member?(words, &1)))}
      end)
      |> Enum.filter(fn {_, n} -> n > 0 end)
      |> Enum.sort_by(fn {a, n} -> {-n, a.id} end)

    case ranked do
      [{a, _}] -> a
      [{a, n}, {_, m} | _] when n > m -> a
      _ -> nil
    end
  end
end
