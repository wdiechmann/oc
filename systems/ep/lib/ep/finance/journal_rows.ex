defmodule Ep.Finance.JournalRows do
  @moduledoc "Paired work rows with transactional, never-reused per-book enclosure numbers."
  import Ecto.Query
  alias Ep.Repo

  alias Ep.Finance.{
    Account,
    JournalAttachment,
    JournalCounter,
    JournalRow,
    VatRule,
    VatRules,
    CatalogueEntry
  }

  @keys ~w(id reference debit_account_id credit_account_id amount_minor amount_basis void)
  def input(row) do
    row
    |> Map.take(
      @keys ++
        [
          "basis_override",
          "credit_amount_minor",
          "vat_enabled",
          "vat_entry_id",
          "vat_source_side"
        ]
    )
    |> Map.put_new("credit_amount_minor", if(row["posting_id"], do: row["amount_minor"]))
  end

  def expand!(tid, bid, data) do
    rows = data["rows"]
    unless is_list(rows) && length(rows) <= 100, do: Repo.rollback(:invalid_journal)

    rows =
      Enum.map(rows, fn row ->
        unless is_map(row) &&
                 Enum.sort(
                   Map.keys(
                     Map.drop(row, [
                       "basis_override",
                       "credit_amount_minor",
                       "vat_enabled",
                       "vat_entry_id",
                       "vat_source_side"
                     ])
                   )
                 ) ==
                   Enum.sort(@keys) &&
                 (not Map.has_key?(row, "vat_enabled") || is_boolean(row["vat_enabled"])) &&
                 is_integer(row["amount_minor"]) &&
                 row["amount_minor"] in -9_000_000_000_000..9_000_000_000_000 &&
                 row["amount_basis"] in [nil, "gross", "net"] &&
                 is_boolean(Map.get(row, "basis_override", !is_nil(row["amount_basis"]))) &&
                 (is_nil(row["credit_amount_minor"]) ||
                    (is_integer(row["credit_amount_minor"]) &&
                       row["credit_amount_minor"] in -9_000_000_000_000..9_000_000_000_000)) &&
                 is_boolean(row["void"]) &&
                 is_binary(row["reference"]) && String.length(row["reference"]) <= 120 &&
                 !Regex.match?(~r/[\p{Cc}\p{Cf}]/u, row["reference"]),
               do: Repo.rollback(:invalid_journal)

        row =
          row
          |> Map.update!("amount_minor", &abs/1)
          |> Map.update("credit_amount_minor", nil, fn value ->
            if is_integer(value), do: abs(value), else: value
          end)

        id = if row["id"] in [nil, ""], do: Ecto.UUID.generate(), else: uuid!(row["id"])
        existing = Repo.get_by(JournalRow, tenant_id: tid, book_id: bid, id: id)

        row =
          Map.merge(row, %{
            "id" => id,
            "posting_id" => existing && existing.posting_id,
            "debit_line_id" =>
              (existing && existing.data["debit_line_id"]) || Ecto.UUID.generate(),
            "credit_line_id" =>
              (existing && existing.data["credit_line_id"]) || Ecto.UUID.generate(),
            "attachments" => attachment_metadata(tid, bid, id)
          })

        Enum.each(~w(debit_account_id credit_account_id), fn key ->
          if row[key] && !Repo.get_by(Account, tenant_id: tid, book_id: bid, id: uuid!(row[key])),
            do: Repo.rollback(:invalid_account_reference)
        end)

        accounts =
          Enum.map(~w(debit_account_id credit_account_id), fn key ->
            if row[key],
              do: Repo.get_by(Account, tenant_id: tid, book_id: bid, id: uuid!(row[key]))
          end)
          |> Enum.reject(&is_nil/1)

        if row["vat_entry_id"] do
          entry =
            Repo.get_by(CatalogueEntry,
              id: uuid!(row["vat_entry_id"]),
              tenant_id: tid,
              book_id: bid,
              kind: "vat"
            )

          unless row["vat_source_side"] in ~w(debit credit) && entry,
            do: Repo.rollback(:invalid_vat_reference)
        else
          if row["vat_source_side"], do: Repo.rollback(:invalid_vat_reference)
        end

        accounts =
          if row["vat_entry_id"] do
            Enum.map(accounts, fn account ->
              %{
                account
                | vat_entry_id:
                    if(account.id == row[row["vat_source_side"] <> "_account_id"],
                      do: row["vat_entry_id"],
                      else: nil
                    )
              }
            end)
          else
            accounts
          end

        override = Map.get(row, "basis_override", !is_nil(row["amount_basis"]))
        explicit_vat = Map.has_key?(row, "vat_enabled") || not is_nil(row["vat_entry_id"])

        if !explicit_vat && override && is_nil(row["amount_basis"]),
          do: Repo.rollback(:invalid_journal)

        vat_account = Enum.find(accounts, & &1.vat_entry_id)

        basis =
          if explicit_vat do
            if vat_account && vat_account.id != row["debit_account_id"], do: "gross", else: "net"
          else
            if override, do: row["amount_basis"], else: default_basis(accounts)
          end

        calculation_accounts = if row["vat_enabled"] == false, do: [], else: accounts

        {suggested, posting_debit} =
          suggested_amounts(
            calculation_accounts,
            row["debit_account_id"],
            basis,
            row["amount_minor"],
            Date.from_iso8601!(data["posting_date"])
          )

        total = row["credit_amount_minor"] || suggested

        unless is_nil(total) || total in -9_000_000_000_000..9_000_000_000_000,
          do: Repo.rollback(:invalid_amount)

        row
        |> Map.put("basis_override", override)
        |> Map.put("amount_basis", basis)
        |> Map.put("posting_debit_minor", posting_debit)
        |> Map.put("suggested_credit_minor", suggested)
        |> Map.put("credit_total_minor", total)
      end)

    unless length(Enum.uniq_by(rows, & &1["id"])) == length(rows),
      do: Repo.rollback(:invalid_journal)

    lines =
      rows
      |> Enum.reject(& &1["void"])
      |> Enum.flat_map(fn row ->
        sides =
          if row["debit_account_id"] || row["credit_account_id"],
            do: Enum.filter(~w(debit credit), &(row[&1 <> "_account_id"] != nil)),
            else: ["debit"]

        Enum.map(sides, fn side ->
          a =
            if row[side <> "_account_id"],
              do:
                Repo.get_by(Account, tenant_id: tid, book_id: bid, id: row[side <> "_account_id"])

          vat =
            cond do
              row["vat_enabled"] == false ->
                nil

              row["vat_entry_id"] ->
                if side == row["vat_source_side"], do: row["vat_entry_id"], else: nil

              true ->
                a && a.vat_entry_id
            end

          date = Date.from_iso8601!(data["posting_date"])

          rule =
            if vat,
              do:
                Repo.one(
                  from r in VatRule,
                    where:
                      r.book_id == ^bid and r.vat_entry_id == ^vat and r.active and
                        r.valid_from <= ^date and
                        (is_nil(r.valid_until) or r.valid_until >= ^date)
                )

          sign =
            if rule && rule.direction == "output",
              do: if(side == "credit", do: 1, else: -1),
              else: if(side == "debit", do: 1, else: -1)

          value =
            if side == "debit", do: row["amount_minor"], else: row["credit_total_minor"] || 0

          debit? = side == "debit"

          %{
            "id" => row[side <> "_line_id"],
            "account_id" => a && a.id,
            "reference" => row["reference"],
            "debit_minor" => if(debit?, do: abs(value), else: 0),
            "credit_minor" => if(debit?, do: 0, else: abs(value)),
            "vat_entry_id" => vat,
            "net_minor" => if(vat, do: sign * row["amount_minor"]),
            "assessed_vat_minor" => nil
          }
        end)
      end)

    {rows, lines}
  end

  defp suggested_amounts(accounts, debit_id, basis, amount, date) do
    account = Enum.find(accounts, & &1.vat_entry_id)

    cond do
      is_nil(account) ->
        {amount, amount}

      is_nil(basis) ->
        {nil, amount}

      true ->
        rule =
          Repo.one(
            from r in VatRule,
              where:
                r.book_id == ^account.book_id and r.vat_entry_id == ^account.vat_entry_id and
                  r.active and r.valid_from <= ^date and
                  (is_nil(r.valid_until) or r.valid_until >= ^date)
          )

        if rule do
          result =
            if basis == "gross" && rule.direction in ~w(input output),
              do: VatRules.calculate_gross(rule, date, amount),
              else: VatRules.calculate(rule, date, amount, nil)

          case result do
            {:ok, quote} ->
              net = quote.amounts["net"]

              follows =
                rule.direction in ~w(input reverse_charge) &&
                  is_nil((rule.posting_accounts || %{})["non_deductible"])

              cost = net + if(follows, do: quote.amounts["non_deductible_vat"], else: 0)
              invoice = quote.invoice_total_minor
              if account.id == debit_id, do: {invoice, cost}, else: {cost, invoice}

            _ ->
              {nil, amount}
          end
        else
          {nil, amount}
        end
    end
  end

  defp default_basis(accounts) do
    taxed = Enum.filter(accounts, & &1.vat_entry_id)

    if taxed == [] do
      Enum.find_value(accounts, & &1.vat_basis)
    else
      case Enum.uniq(Enum.map(taxed, & &1.vat_basis)) do
        [basis] -> basis
        _ -> nil
      end
    end
  end

  def assign!(tid, bid, did, data) do
    unless Repo.in_transaction?(),
      do: raise("Posting ID allocation requires a draft acceptance transaction")

    Ep.Events.lock!("finance-setup:" <> bid)

    if data["rows"] do
      existing =
        Repo.all(
          from r in JournalRow,
            where: r.tenant_id == ^tid and r.book_id == ^bid and r.draft_id == ^did
        )

      unless Enum.all?(existing, fn r -> Enum.any?(data["rows"], &(&1["id"] == r.id)) end),
        do: Repo.rollback(:numbered_row_cannot_disappear)

      counter = Repo.get(JournalCounter, bid) || Repo.insert!(%JournalCounter{book_id: bid})

      {rows, last} =
        Enum.map_reduce(data["rows"], counter.last_number, fn row, last ->
          old = Repo.get(JournalRow, row["id"])

          if old && (old.tenant_id != tid || old.book_id != bid || old.draft_id != did),
            do: Repo.rollback(:invalid_journal)

          number = if old, do: old.posting_id, else: last + 1
          row = Map.put(row, "posting_id", number)

          if old,
            do: Repo.update!(Ecto.Changeset.change(old, data: row)),
            else:
              Repo.insert!(%JournalRow{
                id: row["id"],
                tenant_id: tid,
                book_id: bid,
                draft_id: did,
                posting_id: number,
                data: row
              })

          {row, max(last, number)}
        end)

      Repo.update!(Ecto.Changeset.change(counter, last_number: last))
      Map.put(data, "rows", rows)
    else
      data
    end
  end

  def attachment_metadata(tid, bid, row_id),
    do:
      Repo.all(
        from a in JournalAttachment,
          where: a.tenant_id == ^tid and a.book_id == ^bid and a.row_id == ^row_id,
          order_by: a.inserted_at,
          select: map(a, [:id, :filename, :content_type, :sha256, :byte_size])
      )
      |> Enum.map(fn m -> Map.new(m, fn {k, v} -> {Atom.to_string(k), v} end) end)

  defp uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_journal)
    end
  end
end
