defmodule Ep.Finance.ChartImportPlan do
  @moduledoc "Non-writing, whole-chart validation for a bounded reviewed import."
  alias Ep.Finance.{AccountRules, Formula, CatalogueEntry}
  alias Ep.Repo

  @fields ~w(id number name kind position active formula formula_refs vat_entry_id category_entry_id vat_entry_version category_entry_version vat_code category version retired)a
  @material ~w(number name kind position active formula formula_refs vat_entry_id category_entry_id retired)a

  def build(
        tid,
        bid,
        headers,
        records,
        mapping,
        current,
        version,
        ids \\ %{},
        event_ids \\ %{},
        proposed \\ [],
        mode \\ "merge"
      ) do
    rows =
      records
      |> Enum.with_index(2)
      |> Enum.map(fn {values, line} ->
        record = Map.new(Enum.zip(headers, values))
        prior = if line > 2, do: Map.new(Enum.zip(headers, Enum.at(records, line - 3))), else: %{}
        kind = guessed_kind(record, mapping, prior)
        inferred = if String.trim(to_string(value(record, mapping, "type"))) == "", do: kind

        try do
          check_scope!(record, mapping, "schema_version", "1")
          check_scope!(record, mapping, "tenant_id", tid)
          check_scope!(record, mapping, "book_id", bid)
          check_scope!(record, mapping, "source_version", to_string(version - length(proposed)))
          params = parameters(record, mapping, kind)
          previous = previous!(record, mapping, params, current)

          account_version =
            Map.get(record, "account_version", value(record, mapping, "account_version"))

          if present?(account_version) &&
               (!previous || integer!(account_version) != previous.version),
             do: fail!(:version_conflict)

          id = (previous && previous.id) || ids[to_string(line)] || Ecto.UUID.generate()
          params = defaults(params, previous)
          params = reference!(tid, bid, record, mapping, params, "vat", previous, proposed)
          params = reference!(tid, bid, record, mapping, params, "category", previous, proposed)

          %{
            line: line,
            id: id,
            event_id:
              event_ids[to_string(line)] || if(previous, do: Ecto.UUID.generate(), else: id),
            previous: previous,
            params: params,
            source: record,
            inferred_type: inferred,
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
              inferred_type: inferred,
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

    remaining = if mode == "replace", do: [], else: Enum.reject(current, & &1.retired)

    prospective =
      (Enum.reject(remaining, &MapSet.member?(targets, &1.id)) ++
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
            case AccountRules.validate(
                   row.params,
                   tid,
                   bid,
                   row.id,
                   row.previous,
                   prospective,
                   proposed
                 ) do
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
                  else:
                    Map.put(
                      row,
                      :attrs,
                      Map.merge(attrs, %{active: row.params["active"], retired: false})
                    )
            end
        end
      end)

    final_chart =
      (Enum.reject(remaining, &MapSet.member?(targets, &1.id)) ++
         Enum.filter(rows, &(&1.errors == [])))
      |> Enum.map(fn
        %{attrs: attrs, id: id} -> Map.put(attrs, :id, id)
        account -> account
      end)

    global_errors =
      if Enum.all?(rows, &(&1.errors == [])) && !Formula.acyclic?(final_chart),
        do: ["invalid_formula_cycle_or_reference"],
        else: []

    {review, last_version} =
      Enum.map_reduce(rows, version, fn row, v ->
        if row.errors == [] do
          unchanged =
            row.previous && Map.take(row.previous, @material) == Map.take(row.attrs, @material)

          operation =
            cond do
              unchanged -> "unchanged"
              row.previous && row.previous.retired -> "restore"
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
             "inferred_type" => row.inferred_type,
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
             "inferred_type" => row.inferred_type,
             "before" => nil,
             "after" => nil,
             "source" => row.source,
             "errors" => row.errors
           }, v}
        end
      end)

    retired =
      if mode == "replace",
        do: Enum.reject(current, &(&1.retired || MapSet.member?(targets, &1.id))),
        else: []

    {retirements, _} =
      retired
      |> Enum.sort_by(&{&1.position, &1.id})
      |> Enum.map_reduce(last_version, fn account, v ->
        {%{
           "account_id" => account.id,
           "event_id" => event_ids["retire:" <> account.id] || Ecto.UUID.generate(),
           "operation" => "retire",
           "before" => stringify(Map.take(account, @fields)),
           "after" =>
             account
             |> Map.take(@fields)
             |> Map.merge(%{retired: true, active: false, version: v + 1})
             |> stringify(),
           "errors" => []
         }, v + 1}
      end)

    counts = Enum.frequencies_by(review, & &1["operation"])

    counts =
      if retirements == [], do: counts, else: Map.put(counts, "retire", length(retirements))

    %{
      "rows" => review,
      "mode" => mode,
      "retirements" => retirements,
      "retained_count" => Enum.count(rows, &(&1.previous && !&1.previous.retired)),
      "errors" => global_errors,
      "valid" => global_errors == [] && Enum.all?(review, &(&1["errors"] == [])),
      "counts" => counts
    }
  end

  defp guessed_kind(record, mapping, prior) do
    explicit = value(record, mapping, "type") |> to_string() |> String.downcase() |> String.trim()

    prior_type =
      value(prior, mapping, "type") |> to_string() |> String.downcase() |> String.trim()

    prior_posting =
      prior_type == "posting" || (prior_type == "" && present?(value(prior, mapping, "number")))

    cond do
      explicit != "" -> explicit
      present?(value(record, mapping, "number")) -> "posting"
      present?(value(record, mapping, "formula")) || prior_posting -> "calculation"
      true -> "header"
    end
  end

  defp parameters(record, mapping, kind) do
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

    defaults =
      if previous && previous.retired, do: Map.put(defaults, "active", true), else: defaults

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

  defp reference!(tid, bid, record, mapping, p, kind, previous, proposed) do
    {id_field, code_field, legacy_field} =
      if kind == "vat",
        do: {"vat_entry_id", "vat_code", "vat_code"},
        else: {"category_entry_id", "category_code", "category"}

    id = value(record, mapping, id_field)
    code = value(record, mapping, code_field)
    code = if is_binary(code), do: String.trim(code), else: code

    cond do
      present?(id) ->
        id = uuid!(id)

        entry =
          Repo.get_by(CatalogueEntry, tenant_id: tid, book_id: bid, kind: kind, id: id) ||
            Enum.find(
              proposed,
              &(&1.tenant_id == tid && &1.book_id == bid && &1.kind == kind && &1.id == id)
            ) ||
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
