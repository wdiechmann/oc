defmodule Ep.Finance.ChartImportCatalogues do
  @moduledoc "Non-writing proposals for unique missing import VAT/category codes."
  import Ecto.Query
  alias Ep.{Repo, Finance.CatalogueEntry}

  def plan(tid, bid, headers, records, mapping, version, seeds \\ []) do
    existing =
      Repo.all(from e in CatalogueEntry, where: e.tenant_id == ^tid and e.book_id == ^bid)

    values =
      for kind <- ~w(vat category),
          values <- records,
          header = mapping[kind <> "_code"],
          header != nil,
          code = Enum.at(values, Enum.find_index(headers, &(&1 == header))),
          code != "",
          do: {kind, String.trim(code)}

    values = Enum.uniq_by(values, fn {kind, code} -> {kind, String.downcase(code)} end)

    {entries, errors} =
      Enum.reduce(values, {[], []}, fn {kind, code}, {entries, errors} ->
        normalized = String.downcase(code)

        cond do
          Enum.any?(existing, &(&1.kind == kind && String.downcase(&1.code) == normalized)) ->
            {entries, errors}

          !Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/, code) ->
            {entries, errors ++ ["invalid_catalogue_code: #{kind} #{code}"]}

          Enum.any?(existing, &(&1.kind == kind && normalized in &1.reserved_codes)) ->
            {entries, errors ++ ["reserved_catalogue_code: #{kind} #{code}"]}

          true ->
            seed = Enum.find(seeds, &(&1["kind"] == kind && &1["code"] == code))

            entry = %{
              "id" => (seed && seed["id"]) || Ecto.UUID.generate(),
              "kind" => kind,
              "code" => code,
              "name" => code,
              "version" => version + length(entries) + 1
            }

            {entries ++ [entry], errors}
        end
      end)

    proposed =
      Enum.map(entries, fn e ->
        %CatalogueEntry{
          id: e["id"],
          tenant_id: tid,
          book_id: bid,
          kind: e["kind"],
          code: e["code"],
          name: e["name"],
          version: e["version"],
          active: true
        }
      end)

    {entries, proposed, errors}
  end
end
