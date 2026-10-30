defmodule Ep.Finance.Formula do
  @moduledoc "Validates arithmetic formula text and pins bracketed account references to stable IDs. Never evaluates code."

  def references(text, accounts, previous \\ nil)

  def references(text, accounts, previous)
      when is_binary(text) and byte_size(text) <= 2000 do
    tokens =
      Regex.scan(
        ~r/\[(?:@[0-9a-fA-F-]{36}|[A-Za-z0-9][A-Za-z0-9._-]{0,39})\]|\d+(?:\.\d+)?|[+*\/()-]|\S/,
        text
      )
      |> List.flatten()

    with {:ok, []} <- expression(tokens),
         {:ok, refs} <- bind(tokens, accounts, previous, text) do
      {:ok, refs}
    else
      _ -> {:error, :invalid_formula}
    end
  end

  def references(_, _, _), do: {:error, :invalid_formula}

  def acyclic?(accounts) do
    by_id = Map.new(accounts, &{&1.id, &1})

    Enum.reduce_while(Enum.reject(accounts, &(&1.kind == "header")), MapSet.new(), fn row, done ->
      case visit(row.id, by_id, MapSet.new(), done) do
        {:ok, done} -> {:cont, done}
        :error -> {:halt, :error}
      end
    end) != :error
  end

  defp visit(id, rows, path, done) do
    cond do
      MapSet.member?(path, id) ->
        :error

      MapSet.member?(done, id) ->
        {:ok, done}

      is_nil(rows[id]) or rows[id].kind == "header" ->
        :error

      true ->
        result =
          Enum.reduce_while(Map.values(rows[id].formula_refs || %{}), done, fn target, done ->
            case visit(target, rows, MapSet.put(path, id), done) do
              {:ok, done} -> {:cont, done}
              :error -> {:halt, :error}
            end
          end)

        if result == :error, do: :error, else: {:ok, MapSet.put(result, id)}
    end
  end

  defp bind(tokens, accounts, previous, text) do
    by_number = Map.new(accounts, &{&1.number, &1.id})
    refs = tokens |> Enum.filter(&String.starts_with?(&1, "[")) |> Enum.uniq()

    result =
      Map.new(refs, fn token ->
        number = String.slice(token, 1, String.length(token) - 2)

        pinned =
          if previous && previous.formula == text, do: (previous.formula_refs || %{})[number]

        {number,
         pinned ||
           if(String.starts_with?(number, "@"),
             do: String.downcase(String.trim_leading(number, "@")),
             else: by_number[number]
           )}
      end)

    if Enum.all?(result, fn {_, id} -> not is_nil(id) end),
      do: {:ok, result},
      else: {:error, :invalid_formula}
  end

  defp expression(tokens) do
    with {:ok, rest} <- term(tokens), do: additions(rest)
  end

  defp additions([op | tail]) when op in ["+", "-"] do
    with {:ok, rest} <- term(tail), do: additions(rest)
  end

  defp additions(rest), do: {:ok, rest}

  defp term(tokens) do
    with {:ok, rest} <- factor(tokens), do: products(rest)
  end

  defp products([op | tail]) when op in ["*", "/"] do
    with {:ok, rest} <- factor(tail), do: products(rest)
  end

  defp products(rest), do: {:ok, rest}
  defp factor([op | tail]) when op in ["+", "-"], do: factor(tail)

  defp factor(["(" | tail]) do
    case expression(tail) do
      {:ok, [")" | rest]} -> {:ok, rest}
      _ -> :error
    end
  end

  defp factor([token | rest]) do
    if Regex.match?(
         ~r/^(?:\d+(?:\.\d+)?|\[(?:@[0-9a-fA-F-]{36}|[A-Za-z0-9][A-Za-z0-9._-]{0,39})\])$/,
         token
       ),
       do: {:ok, rest},
       else: :error
  end

  defp factor(_), do: :error
end
