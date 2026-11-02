defmodule Ep.Finance.ChartImportPlan do
  @moduledoc "Non-writing, whole-chart validation for a bounded reviewed import."
  alias Ep.Finance.{AccountRules, Formula, CatalogueEntry}
  alias Ep.Repo

  @fields ~w(id number name kind position active formula formula_refs vat_entry_id category_entry_id vat_entry_version category_entry_version vat_code category version)a
  @material ~w(number name kind position active formula formula_refs vat_entry_id category_entry_id)a

  def build(tid, bid, headers, records, mapping, current, version, ids \\ %{}, event_ids \\ %{}) do
    rows =
      records
      |> Enum.with_index(2)
      |> Enum.map(fn {values, line} ->
        record = Map.new(Enum.zip(headers, values))

        try do
          check_scope!(record, mapping, "schema_version", "1")
          check_scope!(record, mapping, "tenant_id", tid)
          check_scope!(record, mapping, "book_id", bid)
          check_scope!(record, mapping, "source_version", to_string(version))
          params = parameters(record, mapping, current)
          previous = previous!(record, mapping, params, current)

          account_version =
            Map.get(record, "account_version", value(record, mapping, "account_version"))

          if present?(account_version) &&
               (!previous || integer!(account_version) != previous.version),
             do: fail!(:version_conflict)

          id = (previous && previous.id) || ids[to_string(line)] || Ecto.UUID.generate()
          params = defaults(params, previous)
          params = reference!(tid, bid, record, mapping, params, "vat", previous)
          params = reference!(tid, bid, record, mapping, params, "category", previous)

          %{
            line: line,
            id: id,
            event_id:
              event_ids[to_string(line)] || if(previous, do: Ecto.UUID.generate(), else: id),
            previous: previous,
            params: params,
            source: record,
            errors: []
          }
        catch
          {:csv_row, error} ->
            %{
              line: line,
              id: nil,
              event_id: nil,
              previous: nil,
              params: %{},
              source: record,
              errors: [Atom.to_string(error)]
            }
        end
      end)

    duplicate_ids =
      rows
      |> Enum.reject(&is_nil(&1.id))
      |> Enum.frequencies_by(& &1.id)
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Enum.map(&elem(&1, 0))

    targets = MapSet.new(Enum.map(rows, & &1.id))

    prospective =
      (Enum.reject(current, &MapSet.member?(targets, &1.id)) ++
         Enum.filter(rows, &(&1.errors == [])))
      |> Enum.map(fn
        %{params: p, id: id, previous: old} ->
          %{
            id: id,
            kind: p["kind"],
            number: if(p["kind"] == "posting", do: p["number"]),
            position: p["position"],
            formula_refs: (old && old.formula_refs) || %{}
          }

        account ->
          account
      end)

    rows =
      Enum.map(rows, fn row ->
        cond do
          row.errors != [] ->
            row

          row.id in duplicate_ids ->
            %{row | errors: ["duplicate_account"]}

          true ->
            case AccountRules.validate(row.params, tid, bid, row.id, row.previous, prospective) do
              {:error, error} ->
                %{row | errors: [Atom.to_string(error)]}

              {:ok, attrs} ->
                taken =
                  attrs.number &&
                    Enum.any?(current, &(&1.id != row.id && attrs.number in &1.reserved_numbers))

                duplicated =
                  attrs.number && Enum.count(prospective, &(&1.number == attrs.number)) > 1

                if taken || duplicated,
                  do: %{row | errors: ["number_taken"]},
                  else: Map.put(row, :attrs, Map.put(attrs, :active, row.params["active"]))
            end
        end
      end)

    final_chart =
      (Enum.reject(current, &MapSet.member?(targets, &1.id)) ++
         Enum.filter(rows, &(&1.errors == [])))
      |> Enum.map(fn
        %{attrs: attrs, id: id} -> Map.put(attrs, :id, id)
        account -> account
      end)

    global_errors =
      if Enum.all?(rows, &(&1.errors == [])) && !Formula.acyclic?(final_chart),
        do: ["invalid_formula_cycle_or_reference"],
        else: []

    {review, _} =
      Enum.map_reduce(rows, version, fn row, v ->
        if row.errors == [] do
          unchanged =
            row.previous && Map.take(row.previous, @material) == Map.take(row.attrs, @material)

          operation =
            cond do
              unchanged -> "unchanged"
              row.previous -> "revise"
              true -> "create"
            end

          next = if unchanged, do: v, else: v + 1

          after_row =
            if unchanged do
              stringify(Map.take(row.previous, @fields))
            else
              row.attrs
              |> Map.put(:id, row.id)
              |> Map.put(:version, next)
              |> stringify()
            end

          {%{
             "line" => row.line,
             "account_id" => row.id,
             "event_id" => row.event_id,
             "operation" => operation,
             "before" => row.previous && stringify(Map.take(row.previous, @fields)),
             "after" => after_row,
             "errors" => []
           }, next}
        else
          {%{
             "line" => row.line,
             "account_id" => row.id,
             "event_id" => row.event_id,
             "operation" => "error",
             "before" => nil,
             "after" => nil,
             "source" => row.source,
             "errors" => row.errors
           }, v}
        end
      end)

    %{
      "rows" => review,
      "errors" => global_errors,
      "valid" => global_errors == [] && Enum.all?(review, &(&1["errors"] == [])),
      "counts" => Enum.frequencies_by(review, & &1["operation"])
    }
  end

  defp parameters(record, mapping, _current) do
    kind = value(record, mapping, "type") |> to_string() |> String.downcase() |> String.trim()

    kind =
      case kind do
        "heading" -> "header"
        "total" -> "calculation"
        other -> other
      end

    fields =
      Enum.reduce(~w(number name position formula active), %{"kind" => kind}, fn field, p ->
        if mapping[field], do: Map.put(p, field, value(record, mapping, field)), else: p
      end)

    fields =
      if Map.has_key?(fields, "position"),
        do: Map.update!(fields, "position", &integer!/1),
        else: fields

    if Map.has_key?(fields, "active"),
      do: Map.update!(fields, "active", &boolean!/1),
      else: fields
  end

  defp defaults(params, previous) do
    defaults =
      if previous,
        do: previous |> Map.take(~w(number name position formula active)a) |> stringify(),
        else: %{"active" => true, "number" => nil, "formula" => nil}

    Map.merge(defaults, params)
  end

  defp previous!(record, mapping, p, current) do
    id = value(record, mapping, "account_id")

    cond do
      present?(id) ->
        id = uuid!(id)
        Enum.find(current, &(&1.id == id)) || fail!(:unknown_account)

      p["kind"] == "posting" && present?(p["number"]) ->
        Enum.find(current, &(&1.number == p["number"]))

      true ->
        nil
    end
  end

  defp reference!(tid, bid, record, mapping, p, kind, previous) do
    {id_field, code_field, legacy_field} =
      if kind == "vat",
        do: {"vat_entry_id", "vat_code", "vat_code"},
        else: {"category_entry_id", "category_code", "category"}

    id = value(record, mapping, id_field)
    code = value(record, mapping, code_field)

    cond do
      present?(id) ->
        id = uuid!(id)

        entry =
          Repo.get_by(CatalogueEntry, tenant_id: tid, book_id: bid, kind: kind, id: id) ||
            fail!(:invalid_catalogue_reference)

        if present?(code) && code != entry.code, do: fail!(:catalogue_mismatch)
        Map.put(p, id_field, id)

      present?(code) ->
        Map.put(p, legacy_field, code)

      mapping[id_field] || mapping[code_field] ->
        Map.put(p, id_field, nil)

      previous ->
        Map.put(p, id_field, Map.get(previous, String.to_existing_atom(id_field)))

      true ->
        Map.put(p, id_field, nil)
    end
  end

  defp check_scope!(record, mapping, field, expected) do
    # Canonical scope/version columns cannot be bypassed by removing their mapping.
    supplied =
      if Map.has_key?(record, field), do: record[field], else: value(record, mapping, field)

    if present?(supplied) && supplied != expected,
      do:
        fail!(
          if(field in ~w(account_version source_version),
            do: :version_conflict,
            else: :scope_or_schema_mismatch
          )
        )
  end

  defp value(record, mapping, field), do: if(mapping[field], do: record[mapping[field]])
  defp present?(s), do: is_binary(s) && s != ""

  defp integer!(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> fail!(:invalid_integer)
    end
  end

  defp integer!(_), do: fail!(:invalid_integer)

  defp boolean!(value) do
    case String.downcase(to_string(value)) do
      "true" -> true
      "false" -> false
      _ -> fail!(:invalid_active)
    end
  end

  defp uuid!(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      _ -> fail!(:invalid_uuid)
    end
  end

  defp fail!(reason), do: throw({:csv_row, reason})
  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
end
