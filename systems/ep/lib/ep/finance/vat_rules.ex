defmodule Ep.Finance.VatRules do
  @moduledoc "Explicit effective-dated VAT configuration. No inferred statutory rates or ledger execution."
  import Ecto.Query
  alias Ep.{Repo, Events}
  alias Ep.Finance.{VatRule, CatalogueEntry, Setup, DanishVatPresets}

  @fields ~w(id tenant_id book_id vat_entry_id valid_from valid_until direction rate_bps deductible_bps mappings assessment_basis preset active version actor_identity_id application_id)a
  @events ~w(VatRuleCreated VatRuleRevised VatRuleDeactivated VatRuleReactivated)
  @components ~w(net vat deductible_vat non_deductible_vat)

  def get(principal, tid, bid) do
    with {:ok, data} <- Setup.get(principal, tid, bid) do
      {:ok,
       data
       |> Map.take([
         :tenant_id,
         :book_id,
         :book_name,
         :status,
         :source_version,
         :latest_version,
         :permissions,
         :catalogues_initialized,
         :vat_rules
       ])
       |> Map.put(:vat_entries, Enum.filter(data.catalogue_entries, &(&1["kind"] == "vat")))
       |> Map.put(:presets, DanishVatPresets.all())}
    end
  end

  def snapshot(bid),
    do:
      Repo.all(
        from r in VatRule,
          where: r.book_id == ^bid,
          order_by: [r.vat_entry_id, r.valid_from, r.id]
      )
      |> Enum.map(&Map.take(&1, @fields))

  def mutate!(tid, bid, action, p, eid, version, actor, app) do
    revise = action == "vat_rule_revise"

    required =
      ~w(vat_entry_id valid_from valid_until direction rate_bps deductible_bps mappings expected_version) ++
        if(revise, do: ~w(rule_id expected_rule_version active), else: [])

    unless Enum.all?(required, &Map.has_key?(p, &1)) &&
             Enum.all?(
               Map.keys(p),
               &(&1 in (required ++ ~w(assessment_basis preset_id preset_version)))
             ),
           do: Repo.rollback(:invalid_vat_rule)

    if Map.has_key?(p, "preset_id") != Map.has_key?(p, "preset_version"),
      do: Repo.rollback(:invalid_vat_preset)

    unless Ep.Finance.Catalogues.initialized?(bid), do: Repo.rollback(:catalogue_not_initialized)

    old =
      if revise,
        do:
          Repo.get_by(VatRule, tenant_id: tid, book_id: bid, id: uuid!(p["rule_id"])) ||
            Repo.rollback(:not_found)

    if old && old.version != p["expected_rule_version"], do: Repo.rollback(:version_conflict)

    entry =
      Repo.get_by(CatalogueEntry,
        tenant_id: tid,
        book_id: bid,
        id: uuid!(p["vat_entry_id"]),
        kind: "vat"
      ) || Repo.rollback(:invalid_vat_reference)

    if old && old.vat_entry_id != entry.id, do: Repo.rollback(:invalid_vat_reference)
    unless old || entry.active, do: Repo.rollback(:inactive_catalogue_entry)
    from = date!(p["valid_from"])
    until = if p["valid_until"] in [nil, ""], do: nil, else: date!(p["valid_until"])
    active = if revise, do: p["active"], else: true
    basis = Map.get(p, "assessment_basis", if(old, do: old.assessment_basis, else: "net"))

    unless basis in ~w(net import_statement) &&
             (basis == "net" || p["direction"] == "reverse_charge"),
           do: Repo.rollback(:invalid_vat_rule)

    unless is_boolean(active) && (is_nil(until) || Date.compare(until, from) != :lt) &&
             p["direction"] in ~w(input output reverse_charge none) && is_integer(p["rate_bps"]) &&
             p["rate_bps"] in 0..10000 &&
             is_integer(p["deductible_bps"]) && p["deductible_bps"] in 0..10000 &&
             (p["direction"] != "output" || p["deductible_bps"] == 0) &&
             (p["direction"] != "none" || (p["rate_bps"] == 0 && p["deductible_bps"] == 0)),
           do: Repo.rollback(:invalid_vat_rule)

    mappings = mappings!(p["mappings"])
    if p["direction"] != "none" && mappings == [], do: Repo.rollback(:invalid_vat_rule)

    if active do
      stop = until || ~D[9999-12-31]
      self = if old, do: old.id, else: eid

      if Repo.exists?(
           from r in VatRule,
             where:
               r.book_id == ^bid and r.vat_entry_id == ^entry.id and r.active and r.id != ^self and
                 r.valid_from <= ^stop and (is_nil(r.valid_until) or r.valid_until >= ^from)
         ),
         do: Repo.rollback(:vat_rule_overlap)
    end

    attrs = %{
      vat_entry_id: entry.id,
      valid_from: from,
      valid_until: until,
      direction: p["direction"],
      rate_bps: p["rate_bps"],
      deductible_bps: p["deductible_bps"],
      mappings: %{"lines" => mappings},
      assessment_basis: basis,
      active: active,
      version: version,
      actor_identity_id: actor,
      application_id: app
    }

    origin = old && old.preset
    preset_id = Map.get(p, "preset_id", origin && origin["id"])
    preset_version = Map.get(p, "preset_version", origin && origin["version"])

    attrs =
      Map.put(
        attrs,
        :preset,
        DanishVatPresets.provenance(preset_id, preset_version, origin, attrs)
      )

    if old,
      do: Repo.update!(Ecto.Changeset.change(old, attrs)),
      else:
        Repo.insert!(struct!(VatRule, Map.merge(attrs, %{id: eid, tenant_id: tid, book_id: bid})))

    cond do
      !old -> "VatRuleCreated"
      old.active && !active -> "VatRuleDeactivated"
      !old.active && active -> "VatRuleReactivated"
      true -> "VatRuleRevised"
    end
  end

  # Posting callers must first authorize the financial operation and keep this transaction open through commit.
  def lock_rule!(tid, bid, entry_id, date) do
    unless Repo.in_transaction?(),
      do: raise("VAT rule selection requires an acceptance transaction")

    tid = uuid!(tid)
    bid = uuid!(bid)
    Events.lock!("finance-setup:" <> bid)

    entry =
      Repo.get_by(CatalogueEntry, id: uuid!(entry_id), tenant_id: tid, book_id: bid, kind: "vat") ||
        Repo.rollback(:invalid_vat_reference)

    unless entry.active, do: Repo.rollback(:inactive_catalogue_entry)
    date = date!(date)

    Repo.one(
      from r in VatRule,
        where:
          r.tenant_id == ^tid and r.book_id == ^bid and r.vat_entry_id == ^entry.id and r.active and
            r.valid_from <= ^date and (is_nil(r.valid_until) or r.valid_until >= ^date),
        lock: "FOR SHARE"
    ) || Repo.rollback(:vat_rule_missing)
  end

  def quote(principal, tid, bid, entry_id, date, net_minor, assessed_vat_minor \\ nil) do
    with {:ok, tid} <- Ecto.UUID.cast(tid), {:ok, bid} <- Ecto.UUID.cast(bid) do
      Repo.transaction(fn ->
        Setup.authorize!(principal, tid, bid)
        Setup.running!(tid)

        unless is_integer(net_minor) && abs(net_minor) <= 9_000_000_000_000,
          do: Repo.rollback(:invalid_amount)

        rule = lock_rule!(tid, bid, entry_id, date)

        case calculate(rule, date!(date), net_minor, assessed_vat_minor) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Pure exact arithmetic for an already scoped, selected rule. Selection and financial authority remain the caller's responsibility."
  def calculate(rule, %Date{} = date, net_minor, assessed_vat_minor \\ nil) do
    if !is_integer(net_minor) || abs(net_minor) > 9_000_000_000_000 do
      {:error, :invalid_amount}
    else
      try do
        vat =
          if rule.assessment_basis == "import_statement" do
            unless is_integer(assessed_vat_minor) &&
                     abs(assessed_vat_minor) <= 9_000_000_000_000 &&
                     (net_minor == 0 || assessed_vat_minor == 0 ||
                        net_minor < 0 == assessed_vat_minor < 0),
                   do: throw(:assessment_required)

            assessed_vat_minor
          else
            unless is_nil(assessed_vat_minor), do: throw(:invalid_amount)
            round_ratio(net_minor * rule.rate_bps, 10000)
          end

        deductible = round_ratio(vat * rule.deductible_bps, 10000)

        amounts = %{
          "net" => net_minor,
          "vat" => vat,
          "deductible_vat" => deductible,
          "non_deductible_vat" => vat - deductible
        }

        reports =
          Enum.reduce(rule.mappings["lines"], %{}, fn m, acc ->
            Map.update(
              acc,
              m["box"],
              amounts[m["component"]] * m["sign"],
              &(&1 + amounts[m["component"]] * m["sign"])
            )
          end)

        result = %{
          rounding: "nearest_minor_half_away_from_zero",
          rule_id: rule.id,
          rule_version: rule.version,
          vat_entry_id: rule.vat_entry_id,
          date: date,
          direction: rule.direction,
          assessment_basis: rule.assessment_basis,
          rate_bps: rule.rate_bps,
          deductible_bps: rule.deductible_bps,
          amounts: amounts,
          invoice_total_minor:
            if(rule.direction in ~w(reverse_charge none),
              do: net_minor,
              else: net_minor + vat
            ),
          reporting: reports
        }

        {:ok, result}
      catch
        reason when reason in [:assessment_required, :invalid_amount] -> {:error, reason}
      end
    end
  end

  def project(snapshot, old, event) do
    previous = Map.new((old || %{})["vat_rules"] || [], &{&1["id"], &1})

    rules =
      Enum.map(snapshot["vat_rules"] || [], fn rule ->
        prior = previous[rule["id"]]
        history = if prior, do: prior["history"] || [], else: []

        history =
          if rule["version"] == event.stream_version &&
               (!prior || prior["version"] != rule["version"]) do
            unless event.event_type in @events &&
                     rule["actor_identity_id"] == event.actor_identity_id &&
                     rule["tenant_id"] == event.tenant_id && rule["book_id"] == event.stream_id,
                   do: Repo.rollback(:projection_scope)

            history ++
              [
                Map.take(
                  rule,
                  ~w(valid_from valid_until direction rate_bps deductible_bps mappings assessment_basis preset active version actor_identity_id application_id)
                )
                |> Map.merge(%{
                  "event_id" => event.id,
                  "event_type" => event.event_type,
                  "accepted_at" => DateTime.to_iso8601(event.inserted_at)
                })
              ]
          else
            history
          end

        Map.put(rule, "history", history)
      end)

    Map.put(snapshot, "vat_rules", rules)
  end

  defp mappings!(list) do
    unless is_list(list) && length(list) <= 4, do: Repo.rollback(:invalid_vat_rule)

    normalized =
      Enum.map(list, fn m ->
        unless is_map(m) && Enum.sort(Map.keys(m)) == ~w(box component sign) &&
                 is_binary(m["box"]) && String.length(String.trim(m["box"])) in 1..60 &&
                 !Regex.match?(~r/[\p{Cc}\p{Cf}]/u, m["box"]) && m["component"] in @components &&
                 m["sign"] in [-1, 1],
               do: Repo.rollback(:invalid_vat_rule)

        Map.put(m, "box", String.trim(m["box"]))
      end)

    unless length(Enum.uniq_by(normalized, &{&1["box"], &1["component"]})) == length(normalized),
      do: Repo.rollback(:invalid_vat_rule)

    normalized
  end

  defp round_ratio(n, d), do: if(n < 0, do: -div(-n + div(d, 2), d), else: div(n + div(d, 2), d))

  defp date!(%Date{year: year} = date) when year in 1..9999, do: date

  defp date!(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, date} when date.year in 1..9999 ->
        if Date.to_iso8601(date) == s, do: date, else: Repo.rollback(:invalid_vat_rule)

      _ ->
        Repo.rollback(:invalid_vat_rule)
    end
  end

  defp date!(_), do: Repo.rollback(:invalid_vat_rule)

  defp uuid!(s) do
    case Ecto.UUID.cast(s) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_vat_reference)
    end
  end
end
