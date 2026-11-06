defmodule Ep.Finance.JournalPostingPreview do
  @moduledoc "Read-only complete journal legs; never authorizes or creates ledger postings."
  alias Ep.Repo
  alias Ep.Finance.{Account, VatRule}

  def build(tid, bid, data, validation) do
    rows = Enum.reject(data["rows"] || [], fn r -> r["void"] || blank?(r) end)
    previews = Enum.map(rows, &row(tid, bid, &1, data, validation))
    legs = Enum.flat_map(previews, & &1["legs"])

    errors =
      Enum.flat_map(previews, & &1["errors"]) ++
        if(rows == [], do: ["empty_journal"], else: []) ++
        if validation["period"] && validation["period"]["status"] == "open",
          do: [],
          else: ["period_not_open"]

    totals(legs, errors) |> Map.put("rows", previews) |> Map.put("unposted", true)
  end

  def numbered(validation, data) do
    ids = Map.new(data["rows"] || [], &{&1["id"], &1["posting_id"]})

    if validation["posting_preview"] do
      update_in(validation, ["posting_preview", "rows"], fn rows ->
        Enum.map(rows, &Map.put(&1, "posting_id", ids[&1["row_id"]]))
      end)
    else
      validation
    end
  end

  defp row(tid, bid, r, data, validation) do
    source = Enum.filter(data["lines"], &(&1["id"] in [r["debit_line_id"], r["credit_line_id"]]))

    checked =
      Enum.filter(validation["lines"], &(&1["id"] in [r["debit_line_id"], r["credit_line_id"]]))

    taxes = Enum.filter(checked, & &1["vat"])

    errors =
      Enum.flat_map(checked, & &1["errors"]) ++
        if(r["debit_account_id"], do: [], else: ["debit_account_required"]) ++
        if r["credit_account_id"], do: [], else: ["credit_account_required"]

    {tax_legs, tax_errors, quote} =
      case taxes do
        [] -> {[], [], nil}
        [%{"vat" => %{"error" => error}}] -> {[], [error], nil}
        [%{"vat" => q}] -> tax_legs(tid, bid, r, q)
        _ -> {[], ["multiple_vat_accounts"], nil}
      end

    base =
      Enum.map(source, fn l ->
        side = if l["id"] == r["debit_line_id"], do: "debit", else: "credit"

        amount =
          if side == "debit",
            do: r["posting_debit_minor"] || abs(r["amount_minor"]),
            else: abs(r["credit_total_minor"] || 0)

        signed_credit = if side == "debit", do: -amount, else: amount
        leg(tid, bid, l["account_id"], side, signed_credit)
      end)

    legs = Enum.map(base, &elem(&1, 0))

    legs =
      Enum.reduce(tax_legs, legs, fn tax, acc ->
        if tax["follows_account"] && Enum.any?(acc, &(&1["role"] == tax["follows_account"])) do
          Enum.map(acc, fn leg ->
            if leg["role"] == tax["follows_account"] do
              leg
              |> Map.put("non_deductible_vat_minor", tax["debit_minor"] + tax["credit_minor"])
            else
              leg
            end
          end)
        else
          acc ++ [tax]
        end
      end)

    amount_errors =
      if Enum.any?(
           legs,
           &(&1["debit_minor"] > 9_000_000_000_000 || &1["credit_minor"] > 9_000_000_000_000)
         ), do: ["posting_amount_out_of_range"], else: []

    errors = errors ++ tax_errors ++ Enum.flat_map(base, &elem(&1, 1)) ++ amount_errors

    totals(legs, errors)
    |> Map.merge(%{
      "row_id" => r["id"],
      "posting_id" => r["posting_id"],
      "legs" => legs,
      "vat_rule" =>
        if(quote, do: Map.take(quote, ~w(rule_id rule_version date direction posting_direction)))
    })
  end

  defp tax_legs(tid, bid, r, q) do
    rule = Repo.get_by(VatRule, id: q["rule_id"], tenant_id: tid, book_id: bid)

    if !rule || rule.version != q["rule_version"] do
      {[], ["vat_rule_changed"], q}
    else
      amounts = q["amounts"]

      parts =
        case q["direction"] do
          "none" ->
            []

          "reverse_charge" ->
            [
              {"output", amounts["vat"]},
              {"input", -amounts["deductible_vat"]},
              {"non_deductible", -amounts["non_deductible_vat"]}
            ]

          "output" ->
            [{"output", amounts["vat"]}]

          _ ->
            [
              {"input", -amounts["deductible_vat"]},
              {"non_deductible", -amounts["non_deductible_vat"]}
            ]
        end

      resolved =
        parts
        |> Enum.reject(fn {_, value} -> value == 0 end)
        |> Enum.map(fn {role, value} ->
          mapped = (rule.posting_accounts || %{})[role]

          if role == "non_deductible" && is_nil(mapped) do
            follows = q["posting_source_side"] || "debit"
            {entry, issues} = leg(tid, bid, r[follows <> "_account_id"], "vat_" <> role, value)
            {Map.put(entry, "follows_account", follows), issues}
          else
            case mapped do
              nil -> {nil, ["vat_posting_account_missing:" <> role]}
              id -> leg(tid, bid, id, "vat_" <> role, value)
            end
          end
        end)

      {resolved |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1),
       Enum.flat_map(resolved, &elem(&1, 1)), q}
    end
  end

  defp leg(tid, bid, id, role, value) do
    account = id && Repo.get_by(Account, id: id, tenant_id: tid, book_id: bid)
    valid = account && account.kind == "posting" && account.active && !account.retired

    {%{
       "role" => role,
       "account" =>
         if(account,
           do:
             Map.new(Map.take(account, ~w(id number name version)a), fn {k, v} ->
               {Atom.to_string(k), v}
             end)
         ),
       "debit_minor" => if(value < 0, do: -value, else: 0),
       "credit_minor" => if(value > 0, do: value, else: 0)
     },
     if(valid, do: [], else: ["posting_account_unavailable:" <> role]) ++
       if(abs(value) <= 9_000_000_000_000, do: [], else: ["posting_amount_out_of_range"])}
  end

  defp totals(legs, errors) do
    debit = Enum.sum(Enum.map(legs, & &1["debit_minor"]))
    credit = Enum.sum(Enum.map(legs, & &1["credit_minor"]))

    errors =
      Enum.uniq(errors ++ if(debit == credit, do: [], else: ["posting_preview_unbalanced"]))

    %{
      "debit_minor" => debit,
      "credit_minor" => credit,
      "difference_minor" => debit - credit,
      "balanced" => debit == credit,
      "errors" => errors,
      "status" => if(errors == [], do: "complete", else: "needs_attention")
    }
  end

  defp blank?(r),
    do:
      r["reference"] in [nil, ""] && !r["debit_account_id"] && !r["credit_account_id"] &&
        r["amount_minor"] == 0 && r["credit_amount_minor"] in [nil, 0] &&
        r["credit_total_minor"] in [nil, 0] && r["attachments"] in [nil, []]
end
