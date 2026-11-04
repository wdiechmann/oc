defmodule Ep.Finance.FormulaPreview do
  @moduledoc "Read-only, revision-fenced chart formula rehearsal with explicit minor-unit test balances."
  alias Ep.Finance.{Formula, Setup}
  @limit 9_000_000_000_000
  @precision_limit Integer.pow(10, 60) - 1

  def get(principal, tid, bid), do: load(principal, tid, bid, nil)
  def preview(principal, tid, bid, params), do: load(principal, tid, bid, params)

  defp load(principal, tid, bid, params) do
    with {:ok, data} <- Setup.get(principal, tid, bid),
         :ok <- ready(data),
         :ok <- bounded(data.accounts),
         {:ok, balances} <- balances(params, data) do
      rows = Setup.normalize_accounts(data.accounts)

      {:ok,
       Map.take(data, [:tenant_id, :book_id, :book_name, :source_version])
       |> Map.merge(%{
         rows:
           Enum.map(
             rows,
             &Map.take(&1, ~w(id number name kind formula formula_refs active position version))
           ),
         balances: balances,
         results: if(params, do: evaluate(rows, balances), else: nil),
         rounding: "nearest_minor_half_away_from_zero",
         max_rows: 2000
       })}
    end
  end

  defp ready(%{status: "ready"}), do: :ok
  defp ready(_), do: {:error, :view_pending}
  defp bounded(rows), do: if(length(rows) <= 2000, do: :ok, else: {:error, :chart_too_large})
  defp balances(nil, _), do: {:ok, %{}}

  defp balances(params, data) when is_map(params) do
    allowed = MapSet.new(for row <- data.accounts, row["kind"] == "posting", do: row["id"])

    cond do
      Enum.sort(Map.keys(params)) != ~w(balances expected_version) ->
        {:error, :invalid_preview}

      not is_integer(params["expected_version"]) ->
        {:error, :invalid_preview}

      params["expected_version"] != data.source_version ->
        {:error, :version_conflict}

      not is_map(params["balances"]) ->
        {:error, :invalid_balances}

      map_size(params["balances"]) > 2000 ->
        {:error, :invalid_balances}

      Enum.any?(params["balances"], fn {id, value} ->
        not MapSet.member?(allowed, id) or not is_integer(value) or abs(value) > @limit
      end) ->
        {:error, :invalid_balances}

      true ->
        {:ok, params["balances"]}
    end
  end

  defp balances(_, _), do: {:error, :invalid_preview}

  @doc "Evaluate accepted, pinned rows without rebinding reference labels to current account numbers."
  def evaluate(rows, balances) do
    accounts = Map.new(rows, &{&1["id"], &1})
    state = %{cache: %{}, remaining: 100_000}

    {results, _} =
      rows
      |> Enum.filter(&(&1["kind"] == "calculation"))
      |> Enum.map_reduce(state, fn row, state ->
        try do
          {value, inputs, state} = account(row["id"], accounts, balances, MapSet.new(), state)
          amount = round_minor(value)
          if abs(amount) > @limit, do: fail(state, :amount_out_of_range, row["id"])

          state = charge(state, MapSet.size(inputs) + map_size(row["formula_refs"] || %{}))

          refs =
            Enum.map(reference_pairs(row), fn {label, id} ->
              {v, _} = state.cache[id]

              Map.merge(describe(accounts[id]), %{
                reference: label,
                amount_minor: round_minor(v),
                exact: exact(v)
              })
            end)
            |> Enum.sort_by(& &1.reference)

          result = %{
            account_id: row["id"],
            status: "ok",
            amount_minor: amount,
            exact: exact(value),
            references: refs,
            inputs:
              inputs
              |> Enum.sort()
              |> Enum.map(fn id ->
                Map.merge(describe(accounts[id]), %{balance_minor: balances[id]})
              end)
          }

          {result, state}
        catch
          {:preview_error, reason, detail, state} ->
            {%{account_id: row["id"], status: "error", error: reason, related_account_id: detail},
             %{state | cache: Map.put(state.cache, row["id"], {:error, reason, detail})}}
        end
      end)

    results
  end

  defp reference_pairs(row) do
    {:ok, _, tokens} = Formula.parse(row["formula"])

    tokens
    |> Enum.filter(&String.starts_with?(&1, "["))
    |> Enum.uniq()
    |> Enum.map(fn token ->
      label = String.slice(token, 1, String.length(token) - 2)
      {label, (row["formula_refs"] || %{})[label]}
    end)
  end

  defp describe(row),
    do: %{
      account_id: row["id"],
      number: row["number"],
      name: row["name"],
      active: row["active"],
      kind: row["kind"]
    }

  defp account(id, accounts, balances, path, state) do
    state = tick(state)
    if MapSet.member?(path, id), do: fail(state, :formula_cycle, id)
    if MapSet.size(path) >= 64, do: fail(state, :complexity_limit, id)

    case state.cache[id] do
      {:error, reason, detail} ->
        fail(state, reason, detail)

      {value, inputs} ->
        {value, inputs, state}

      nil ->
        row = accounts[id]

        unless row && row["kind"] in ~w(posting calculation),
          do: fail(state, :invalid_reference, id)

        {value, inputs, state} =
          if row["kind"] == "posting" do
            unless Map.has_key?(balances, id), do: fail(state, :missing_balance, id)
            {{balances[id], 1}, MapSet.new([id]), state}
          else
            case Formula.parse(row["formula"]) do
              {:ok, ast, _} ->
                expression(
                  ast,
                  row["formula_refs"] || %{},
                  accounts,
                  balances,
                  MapSet.put(path, id),
                  state
                )

              _ ->
                fail(state, :invalid_formula, id)
            end
          end

        if abs(round_minor(value)) > @limit, do: fail(state, :amount_out_of_range, id)
        {value, inputs, %{state | cache: Map.put(state.cache, id, {value, inputs})}}
    end
  end

  defp expression(ast, refs, accounts, balances, path, state) do
    state = tick(state)

    case ast do
      {:number, number} ->
        [whole | fraction] = String.split(number, ".")
        frac = List.first(fraction) || ""

        value =
          rational(String.to_integer(whole <> frac), Integer.pow(10, byte_size(frac)), state)

        {value, MapSet.new(), state}

      {:reference, label} ->
        id = refs[label]
        unless id, do: fail(state, :invalid_reference, nil)
        account(id, accounts, balances, path, state)

      {:unary, op, ast} ->
        {{n, d}, inputs, state} = expression(ast, refs, accounts, balances, path, state)
        {{if(op == "-", do: -n, else: n), d}, inputs, state}

      {:binary, op, left, right} ->
        {{a, b}, inputs, state} = expression(left, refs, accounts, balances, path, state)
        {{c, d}, more, state} = expression(right, refs, accounts, balances, path, state)

        {n, den} =
          case op do
            "+" ->
              {a * d + c * b, b * d}

            "-" ->
              {a * d - c * b, b * d}

            "*" ->
              {a * c, b * d}

            "/" ->
              if c == 0, do: fail(state, :division_by_zero, nil)
              {a * d, b * c}
          end

        state = charge(state, MapSet.size(inputs) + MapSet.size(more))
        {rational(n, den, state), MapSet.union(inputs, more), state}
    end
  end

  defp rational(n, d, state) do
    gcd = Integer.gcd(n, d)
    n = div(n, gcd) * if(d < 0, do: -1, else: 1)
    d = abs(div(d, gcd))
    if abs(n) > @precision_limit or d > @precision_limit, do: fail(state, :complexity_limit, nil)
    {n, d}
  end

  defp exact({n, d}), do: %{numerator: Integer.to_string(n), denominator: Integer.to_string(d)}
  defp round_minor({n, d}), do: div(abs(n) * 2 + d, 2 * d) * if(n < 0, do: -1, else: 1)

  defp charge(state, cost) do
    if state.remaining < cost, do: fail(state, :complexity_limit, nil)
    %{state | remaining: state.remaining - cost}
  end

  defp tick(%{remaining: n} = state) do
    if n <= 0, do: fail(state, :complexity_limit, nil)
    %{state | remaining: n - 1}
  end

  defp fail(state, reason, id), do: throw({:preview_error, reason, id, state})
end
