defmodule Ep.Finance.AccountRules do
  @moduledoc "Non-writing account field/reference validation shared by line editing and CSV plans."
  def validate(p, tid, bid, id, previous, chart, proposed \\ []) do
    try do
      {:ok, checked!(p, tid, bid, id, previous, chart, proposed)}
    catch
      {:account_rule, reason} -> {:error, reason}
    end
  end

  defp reject!(reason), do: throw({:account_rule, reason})

  defp checked!(p, tid, bid, id, previous, rows, proposed) do
    kind =
      case p["kind"] do
        "heading" -> "header"
        "total" -> "calculation"
        other -> other
      end

    name = p["name"]

    position =
      if Map.has_key?(p, "position") do
        p["position"]
      else
        (previous && previous.position) ||
          (Enum.map(rows, & &1.position) |> Enum.max(fn -> 0 end)) + 100
      end

    unless is_binary(name) && String.length(String.trim(name)) in 1..120 &&
             kind in ~w(header calculation posting) && is_integer(position) &&
             position in 1..2_147_483_647,
           do: reject!(:invalid_setup)

    if Enum.any?(rows, &(&1.id != id && &1.position == position)),
      do: reject!(:position_taken)

    number = if kind == "posting", do: p["number"]

    unless kind != "posting" ||
             (is_binary(number) && Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/, number)),
           do: reject!(:invalid_setup)

    selections =
      if kind == "posting" do
        Enum.reduce(["vat", "category"], %{}, fn type, attrs ->
          case Ep.Finance.Catalogues.validate_selection(tid, bid, type, p, previous, proposed) do
            {:ok, selection} -> Map.merge(attrs, selection)
            {:error, reason} -> reject!(reason)
          end
        end)
      else
        %{
          vat_entry_id: nil,
          category_entry_id: nil,
          vat_entry_version: nil,
          category_entry_version: nil,
          vat_code: nil,
          category: nil
        }
      end

    formula = if kind == "calculation", do: p["formula"]
    candidate = %{id: id, number: number, kind: kind, formula_refs: %{}}
    chart = [candidate | Enum.reject(rows, &(&1.id == id))]

    refs =
      if kind == "calculation" do
        case Ep.Finance.Formula.references(formula, chart, previous) do
          {:ok, refs} -> refs
          _ -> reject!(:invalid_formula)
        end
      else
        %{}
      end

    %{
      number: number,
      name: String.trim(name),
      kind: kind,
      position: position,
      formula: formula,
      formula_refs: refs
    }
    |> Map.merge(selections)
  end
end
