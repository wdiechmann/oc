defmodule Ep.Finance.BookOverviewTest do
  use ExUnit.Case, async: true
  alias Ep.Finance.{BookOverview, ReportPresets}
  @income "842cfbde-5b47-40ae-8cda-fb92470ca091"
  @expense "842cfbde-5b47-40ae-8cda-fb92470ca092"
  defp preset do
    accounts = [
      %{"id" => @income, "number" => "1015", "name" => "Income", "category" => "indtægt"},
      %{"id" => @expense, "number" => "2000", "name" => "Expense", "category" => "omkostning"}
    ]

    ReportPresets.profit_loss(accounts, [], 1)
  end

  defp fact(date, income, expenses) do
    %{
      "draft" => %{"data" => %{"posting_date" => date}},
      "posting" => %{
        "accounts" => [
          %{"account" => %{"id" => @income}, "post_minor" => -income},
          %{"account" => %{"id" => @expense}, "post_minor" => expenses}
        ]
      }
    }
  end

  test "fiscal monthly totals, same-date comparison, reversals and inclusive cutoffs" do
    result =
      BookOverview.calculate(
        preset(),
        [
          fact("2026-03-31", 900_000, 0),
          fact("2026-04-01", 150_000, 60000),
          fact("2026-05-01", 60000, 25000),
          fact("2026-05-15", -10000, -5000),
          fact("2026-05-16", 900_000, 0),
          fact("2026-06-01", 900_000, 0),
          fact("2025-04-01", 100_000, 50000),
          fact("2025-05-16", 900_000, 0)
        ],
        ~D[2026-05-15],
        4,
        "DKK"
      )

    assert result.start_date == "2026-04-01"
    assert result.prior_as_of == "2025-05-15"
    assert result.totals == %{income_minor: 200_000, expenses_minor: 80000, profit_minor: 120_000}
    assert result.previous.profit_minor == 50000
    assert result.change_bps == %{income_minor: 10000, expenses_minor: 6000, profit_minor: 14000}
    assert result.journal_count == 3
    assert length(result.months) == 12
    assert hd(result.months).income_minor == 150_000
    assert Enum.at(result.months, 1).expenses_minor == 20000
    assert Enum.at(result.months, 2).future
    assert List.last(result.months).month == "2027-03-01"
  end

  test "leap-day comparison and no invented growth for nonpositive baselines" do
    result =
      BookOverview.calculate(
        preset(),
        [fact("2023-02-28", 100, 200), fact("2023-03-01", 999, 0)],
        ~D[2024-02-29],
        1,
        "DKK"
      )

    assert result.prior_as_of == "2023-02-28"
    assert result.previous.profit_minor == -100
    assert result.change_bps.profit_minor == nil
    assert result.change_bps.income_minor == -10000
    empty = BookOverview.calculate(preset(), [], ~D[2026-01-01], 1, "DKK")
    assert empty.change_bps.income_minor == nil
    assert empty.totals.profit_minor == 0
  end
end
