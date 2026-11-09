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
end
