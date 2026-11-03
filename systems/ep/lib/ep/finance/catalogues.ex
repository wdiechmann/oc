defmodule Ep.Finance.Catalogues do
  @moduledoc "Book-local classification entries and stable account associations. No tax calculation."
  import Ecto.Query
  alias Ep.{Repo, Finance.Account, Finance.CatalogueEntry, Finance.Setup, Finance.SetupState}

  @legacy %{
    "vat" => [{"none", "None"}, {"input", "Input VAT"}, {"output", "Output VAT"}],
    "category" => [
      {"assets", "Assets"},
      {"liabilities", "Liabilities"},
      {"equity", "Equity"},
      {"income", "Income"},
      {"expenses", "Expenses"}
    ]
  }
  @fields ~w(id tenant_id book_id kind code name active version actor_identity_id application_id)a

  def get(principal, tid, bid) do
    with {:ok, data} <- Setup.get(principal, tid, bid) do
      {:ok, Map.drop(data, [:accounts, :bindings, :stewards, :candidates, :occasions])}
    end
  end

  def initialized?(bid) do
    case Repo.get(SetupState, bid) do
      %{catalogues_initialized: true} -> true
      _ -> false
    end
  end

  def snapshot(bid),
    do:
      Repo.all(from e in CatalogueEntry, where: e.book_id == ^bid, order_by: [e.kind, e.code])
      |> Enum.map(&Map.take(&1, @fields))

  def mutate!(tid, bid, "catalogue_initialize", p, _eid, version, actor, app) do
    fields!(p, ~w(expected_version))
    if initialized?(bid), do: Repo.rollback(:catalogues_initialized)

    entries =
      for {kind, values} <- @legacy, {code, name} <- values do
        Repo.insert!(%CatalogueEntry{
          tenant_id: tid,
          book_id: bid,
          kind: kind,
          code: code,
          name: name,
          reserved_codes: [code],
          version: version,
          actor_identity_id: actor,
          application_id: app
        })
      end

    for account <- Repo.all(from a in Account, where: a.book_id == ^bid) do
      changes =
        Enum.reduce(
          [
            {"vat", :vat_code, :vat_entry_id, :vat_entry_version},
            {"category", :category, :category_entry_id, :category_entry_version}
          ],
          %{},
          fn {kind, code_field, id_field, version_field}, attrs ->
            case Map.get(account, code_field) do
              nil ->
                attrs

              code ->
                entry =
                  Enum.find(entries, &(&1.kind == kind && &1.code == code)) ||
                    Repo.rollback(:invalid_catalogue_reference)

                attrs |> Map.put(id_field, entry.id) |> Map.put(version_field, entry.version)
            end
          end
        )

      unless changes == %{},
        do:
          Repo.update!(
            Ecto.Changeset.change(
              account,
              Map.merge(changes, %{
                version: version,
                actor_identity_id: actor,
                application_id: app
              })
            )
          )
    end

    Repo.update!(Ecto.Changeset.change(Repo.get!(SetupState, bid), catalogues_initialized: true))
    "CataloguesInitialized"
  end

  def mutate!(tid, bid, "catalogue_create", p, eid, version, actor, app) do
    fields!(p, ~w(kind code name expected_version))
    ensure_initialized!(bid)
    unless p["kind"] in ~w(vat category), do: Repo.rollback(:invalid_catalogue)
    attrs = attrs!(p)
    reserve!(bid, p["kind"], attrs.code, nil)

    Repo.insert!(
      struct!(
        CatalogueEntry,
        Map.merge(attrs, %{
          id: eid,
          tenant_id: tid,
          book_id: bid,
          kind: p["kind"],
          reserved_codes: [String.downcase(attrs.code)],
          version: version,
          actor_identity_id: actor,
          application_id: app
        })
      )
    )

    "CatalogueEntryCreated"
  end

  def mutate!(tid, bid, "catalogue_revise", p, _eid, version, actor, app) do
    fields!(p, ~w(entry_id code name active expected_version expected_entry_version))
    ensure_initialized!(bid)
    id = uuid!(p["entry_id"])

    row =
      Repo.get_by(CatalogueEntry, tenant_id: tid, book_id: bid, id: id) ||
        Repo.rollback(:not_found)

    unless is_integer(p["expected_entry_version"]) && p["expected_entry_version"] == row.version,
      do: Repo.rollback(:version_conflict)

    unless is_boolean(p["active"]), do: Repo.rollback(:invalid_catalogue)
    attrs = attrs!(p)
    reserve!(bid, row.kind, attrs.code, id)

    attrs =
      Map.merge(attrs, %{
        active: p["active"],
        reserved_codes: Enum.uniq([String.downcase(attrs.code) | row.reserved_codes]),
        version: version,
        actor_identity_id: actor,
        application_id: app
      })

    Repo.update!(Ecto.Changeset.change(row, attrs))

    cond do
      row.active && !attrs.active -> "CatalogueEntryDeactivated"
      !row.active && attrs.active -> "CatalogueEntryReactivated"
      true -> "CatalogueEntryRevised"
    end
  end

  def selection!(tid, bid, kind, params, previous) do
    case validate_selection(tid, bid, kind, params, previous) do
      {:ok, attrs} -> attrs
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def validate_selection(tid, bid, kind, params, previous, proposed \\ []) do
    try do
      {:ok, selection_checked!(tid, bid, kind, params, previous, proposed)}
    catch
      {:catalogue_selection, reason} -> {:error, reason}
    end
  end

  defp selection_error!(reason), do: throw({:catalogue_selection, reason})

  defp selection_uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      _ -> selection_error!(:invalid_catalogue_reference)
    end
  end

  defp selection_checked!(tid, bid, kind, p, previous, proposed) do
    {id_field, code_field, version_field} =
      if kind == "vat",
        do: {:vat_entry_id, :vat_code, :vat_entry_version},
        else: {:category_entry_id, :category, :category_entry_version}

    id_key = Atom.to_string(id_field)
    legacy = p[Atom.to_string(code_field)]
    previous_id = previous && Map.get(previous, id_field)

    if initialized?(bid) do
      entry =
        cond do
          Map.has_key?(p, id_key) && is_nil(p[id_key]) ->
            nil

          Map.has_key?(p, id_key) ->
            Repo.get_by(CatalogueEntry,
              tenant_id: tid,
              book_id: bid,
              kind: kind,
              id: selection_uuid!(p[id_key])
            ) ||
              Enum.find(
                proposed,
                &(&1.tenant_id == tid && &1.book_id == bid && &1.kind == kind &&
                    &1.id == p[id_key])
              ) || selection_error!(:invalid_catalogue_reference)

          is_nil(legacy) ->
            nil

          is_binary(legacy) ->
            Repo.one(
              from e in CatalogueEntry,
                where:
                  e.tenant_id == ^tid and e.book_id == ^bid and e.kind == ^kind and
                    fragment("lower(?)", e.code) == ^String.downcase(legacy)
            ) ||
              own_alias(tid, bid, kind, previous_id, legacy) ||
              Enum.find(
                proposed,
                &(&1.tenant_id == tid && &1.book_id == bid && &1.kind == kind &&
                    String.downcase(&1.code) == String.downcase(legacy))
              ) ||
              selection_error!(:invalid_catalogue_reference)

          true ->
            selection_error!(:invalid_catalogue_reference)
        end

      if entry && !entry.active && entry.id != previous_id,
        do: selection_error!(:inactive_catalogue_entry)

      %{
        id_field => entry && entry.id,
        code_field => entry && entry.code,
        version_field => entry && entry.version
      }
    else
      if Map.has_key?(p, id_key), do: selection_error!(:catalogue_not_initialized)

      unless is_nil(legacy) || legacy in Enum.map(@legacy[kind], &elem(&1, 0)),
        do: selection_error!(:invalid_setup)

      %{id_field => nil, code_field => legacy, version_field => nil}
    end
  end

  defp own_alias(tid, bid, kind, previous_id, legacy) do
    if previous_id do
      entry =
        Repo.get_by(CatalogueEntry, id: previous_id, tenant_id: tid, book_id: bid, kind: kind)

      if entry && String.downcase(legacy) in entry.reserved_codes, do: entry
    end
  end

  def project(snapshot, old, event) do
    previous = Map.new((old || %{})["catalogue_entries"] || [], &{&1["id"], &1})

    entries =
      Enum.map(snapshot["catalogue_entries"] || [], fn entry ->
        prior = previous[entry["id"]]
        history = if prior, do: prior["history"] || [], else: []

        history =
          if entry["version"] == event.stream_version &&
               (!prior || prior["version"] != entry["version"]) do
            unless event.event_type in ~w(CataloguesInitialized CatalogueEntryCreated CatalogueEntryRevised CatalogueEntryDeactivated CatalogueEntryReactivated) &&
                     entry["actor_identity_id"] == event.actor_identity_id,
                   do: Repo.rollback(:projection_scope)

            history ++
              [
                Map.take(entry, ~w(code name active version actor_identity_id application_id))
                |> Map.merge(%{
                  "event_id" => event.id,
                  "event_type" => event.event_type,
                  "accepted_at" => DateTime.to_iso8601(event.inserted_at)
                })
              ]
          else
            history
          end

        Map.put(entry, "history", history)
      end)

    snapshot
    |> Map.put("catalogue_entries", entries)
    |> Map.put_new("catalogues_initialized", false)
  end

  def options(entries),
    do: %{
      vat_codes: Enum.filter(entries, &(&1["kind"] == "vat")),
      categories: Enum.filter(entries, &(&1["kind"] == "category"))
    }

  def labels(account, entries) do
    by_id = Map.new(entries, &{&1["id"], &1})

    account
    |> Map.put("vat_label", label(by_id[account["vat_entry_id"]], account["vat_code"]))
    |> Map.put("category_label", label(by_id[account["category_entry_id"]], account["category"]))
  end

  defp label(nil, legacy), do: legacy
  defp label(entry, _), do: entry["name"] <> if(entry["active"], do: "", else: " (inactive)")

  defp ensure_initialized!(bid),
    do: unless(initialized?(bid), do: Repo.rollback(:catalogue_not_initialized))

  def valid_code?(code) when is_binary(code) do
    code = String.trim(code)
    String.length(code) in 1..120 && !Regex.match?(~r/[\p{Cc}\p{Cf}]/u, code)
  end

  def valid_code?(_), do: false

  defp attrs!(p) do
    code = p["code"]
    name = p["name"]

    unless valid_code?(code) &&
             is_binary(name) && String.length(String.trim(name)) in 1..120,
           do: Repo.rollback(:invalid_catalogue)

    %{code: String.trim(code), name: String.trim(name)}
  end

  defp reserve!(bid, kind, code, self) do
    if Repo.exists?(
         from e in CatalogueEntry,
           where:
             e.book_id == ^bid and e.kind == ^kind and ^String.downcase(code) in e.reserved_codes and
               e.id != ^(self || "00000000-0000-0000-0000-000000000000")
       ),
       do: Repo.rollback(:code_taken)
  end

  defp fields!(p, keys),
    do: unless(Enum.sort(Map.keys(p)) == Enum.sort(keys), do: Repo.rollback(:invalid_catalogue))

  defp uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_catalogue_reference)
    end
  end
end
