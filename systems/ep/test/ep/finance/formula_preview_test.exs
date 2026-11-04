defmodule Ep.Finance.FormulaPreviewTest do
  use ExUnit.Case, async: true
  alias Ep.Finance.{Formula, FormulaPreview}

  defp posting(id, number),
    do: %{"id" => id, "number" => number, "kind" => "posting", "name" => number, "active" => true}

  defp calculation(id, formula, refs),
    do: %{
      "id" => id,
      "kind" => "calculation",
      "name" => id,
      "formula" => formula,
      "formula_refs" => refs,
      "active" => true
    }

  defp result(formula, balances \\ %{"p" => 100}) do
    FormulaPreview.evaluate(
      [posting("p", "0010"), calculation("c", formula, %{"0010" => "p"})],
      balances
    )
    |> hd()
  end

  test "shared grammar handles precedence, unary operators and decimal constants without code execution" do
    assert result("-(2 + 3) * -4 + [0010] / 2").amount_minor == 70
    assert result("12 / 3 / 2 - 5 - 1").amount_minor == -4
    assert result("0.1 + 0.2").exact == %{numerator: "3", denominator: "10"}

    for formula <- [
          "",
          "1 2",
          "1+",
          "(1",
          "1)",
          "1e3",
          "1,2",
          "System.cmd(1)",
          "[bad space]",
          "[0010] ** 2"
        ] do
      assert {:error, :invalid_formula} = Formula.parse(formula)
    end

    assert {:error, :invalid_formula} = Formula.parse(String.duplicate("1", 2001))
  end

  test "nested formulas retain exact fractions and deduplicate contributing balances" do
    rows = [
      posting("p", "0010"),
      calculation("a", "[0010] / 3", %{"0010" => "p"}),
      calculation("b", "[@00000000-0000-0000-0000-000000000000] * 3 + [0010]", %{
        "@00000000-0000-0000-0000-000000000000" => "a",
        "0010" => "p"
      })
    ]

    [a, b] = FormulaPreview.evaluate(rows, %{"p" => 1})
    assert a.amount_minor == 0
    assert a.exact == %{numerator: "1", denominator: "3"}
    assert b.amount_minor == 2
    assert length(b.inputs) == 1
    assert Enum.find(b.references, &(&1.account_id == "a")).exact == a.exact
  end

  test "half-away rounding handles credits and does not silently default missing balances" do
    assert result("[0010] / 2", %{"p" => 1}).amount_minor == 1
    assert result("[0010] / 2", %{"p" => -1}).amount_minor == -1
    assert result("[0010]", %{}).error == :missing_balance
    assert result("[0010]", %{"p" => 0}).amount_minor == 0
    assert result("1 / ([0010] - 100)").error == :division_by_zero
  end

  test "pinned reference identities survive renumbering and positional changes" do
    p = posting("p", "0099") |> Map.put("position", 900)
    c = calculation("c", "[0010] + [0010]", %{"0010" => "p"})
    [r] = FormulaPreview.evaluate([c, p], %{"p" => 4})
    assert r.amount_minor == 8
    assert hd(r.references).number == "0099"
    assert hd(r.references).reference == "0010"
    assert hd(r.inputs).balance_minor == 4
    previous = %{formula: c["formula"], formula_refs: c["formula_refs"]}

    assert {:ok, %{"0010" => "p"}} =
             Formula.references(c["formula"], [%{id: "p", number: "0099"}], previous)
  end

  test "cycles, missing and header references fail explicitly while unrelated formulas still work" do
    rows = [
      posting("p", "0010"),
      %{"id" => "h", "kind" => "header"},
      calculation("a", "[x]", %{"x" => "b"}),
      calculation("b", "[x]", %{"x" => "a"}),
      calculation("m", "[x]", %{"x" => "gone"}),
      calculation("h1", "[x]", %{"x" => "h"}),
      calculation("ok", "[0010]", %{"0010" => "p"})
    ]

    [a, b, m, h, ok] = FormulaPreview.evaluate(rows, %{"p" => 5})
    assert a.error == :formula_cycle && b.error == :formula_cycle
    assert m.error == :invalid_reference && h.error == :invalid_reference
    assert ok.amount_minor == 5
  end

  test "inactive current posting balances are explicit and arithmetic has bounded precision and output" do
    rows = [
      Map.put(posting("p", "0010"), "active", false),
      calculation("c", "[0010]", %{"0010" => "p"})
    ]

    [r] = FormulaPreview.evaluate(rows, %{"p" => -4})
    assert hd(r.inputs).active == false
    assert r.amount_minor == -4
    assert result("9000000000000 + 1").error == :amount_out_of_range
    assert result(String.duplicate("9", 61)).error == :complexity_limit
  end

  test "dependency limits are independent of chart order" do
    a = calculation("a", "9000000000000 + 1", %{})
    b = calculation("b", "[x] - 1", %{"x" => "a"})

    for rows <- [[a, b], [b, a]] do
      results = FormulaPreview.evaluate(rows, %{})
      assert Enum.all?(results, &(&1.error == :amount_out_of_range))
    end
  end

  test "deep dependency graphs stop with a clear complexity error" do
    chain =
      for index <- 1..70 do
        calculation("c#{index}", "[x]", %{"x" => if(index == 70, do: "p", else: "c#{index + 1}")})
      end

    results = FormulaPreview.evaluate(chain ++ [posting("p", "0010")], %{"p" => 1})
    assert hd(results).error == :complexity_limit
  end
end
