defmodule Ep.Finance.ReportPresets do
  @moduledoc "Versioned shipped report definitions; book-specific edits are accepted report definitions."
  @ytd_id "c06dd8cb-91a1-4a99-8541-ff8fdcfca8ad"

  def ytd(accounts, chart_version) do
    lines =
      accounts
      |> Enum.with_index(1)
      |> Enum.map(fn {account, index} ->
        %{
          "id" => account["id"],
          "code" => "A" <> String.replace(account["id"], "-", ""),
          "name" => String.slice("#{account["number"]} · #{account["name"]}", 0, 120),
          "kind" => "mapping",
          "position" => index * 100,
          "account_ids" => [account["id"]],
          "sign" => 1,
          "formula" => nil,
          "formula_refs" => %{}
        }
      end)

    %{
      "id" => @ytd_id,
      "name" => "YTD balances",
      "active" => true,
      "builtin" => true,
      "version" => 1,
      "history" => [],
      "definition" => %{
        "lines" => lines,
        "accounts" => accounts,
        "chart_version" => chart_version
      }
    }
  end

  def profit_loss(accounts, entries, chart_version) do
    groups = Enum.group_by(accounts, &category(&1, entries))
    income = "842cfbde-5b47-40ae-8cda-fb92470ca081"
    expenses = "842cfbde-5b47-40ae-8cda-fb92470ca082"
    profit = "842cfbde-5b47-40ae-8cda-fb92470ca083"

    mapping = fn id, code, name, kind, sign, position ->
      %{
        "id" => id,
        "code" => code,
        "name" => name,
        "kind" => "mapping",
        "position" => position,
        "account_ids" => Enum.map(groups[kind] || [], & &1["id"]),
        "sign" => sign,
        "formula" => nil,
        "formula_refs" => %{}
      }
    end

    %{
      "id" => "842cfbde-5b47-40ae-8cda-fb92470ca080",
      "name" => "Profit and loss",
      "active" => true,
      "builtin" => true,
      "version" => 1,
      "history" => [],
      "classification_warnings" =>
        Enum.map(groups[:unknown] || [], &Map.take(&1, ~w(id number name active))),
      "definition" => %{
        "report_type" => "profit_loss",
        "chart_version" => chart_version,
        "accounts" => accounts,
        "lines" => [
          mapping.(income, "INCOME", "Income", :income, -1, 100),
          mapping.(expenses, "EXPENSES", "Expenses", :expenses, 1, 200),
          %{
            "id" => profit,
            "code" => "PROFIT",
            "name" => "Profit / loss",
            "kind" => "total",
            "position" => 300,
            "account_ids" => [],
            "sign" => 1,
            "formula" => "[INCOME] - [EXPENSES]",
            "formula_refs" => %{"INCOME" => income, "EXPENSES" => expenses}
          }
        ]
      }
    }
  end

  defp category(account, entries) do
    values =
      if account["category_entry_id"] do
        entry =
          Enum.find(
            entries,
            &(&1["kind"] == "category" && &1["id"] == account["category_entry_id"])
          )

        if entry, do: [entry["code"], entry["name"]], else: []
      else
        [account["category"]]
      end

    values = Enum.map(values, &String.downcase(String.trim(&1 || "")))

    cond do
      Enum.any?(
        values,
        &(&1 in ~w(income revenue revenues indtægt indtægter indtaegt indtaegter))
      ) ->
        :income

      Enum.any?(
        values,
        &(&1 in ~w(expense expenses cost costs omkostning omkostninger udgift udgifter))
      ) ->
        :expenses

      Enum.any?(
        values,
        &(&1 in ~w(asset assets aktiv aktiver liability liabilities passiv passiver equity egenkapital))
      ) ->
        :balance

      true ->
        :unknown
    end
  end
end
