defmodule Ep.Finance.Journals do
  @moduledoc "Reviewed, unposted journal preparation and complete posting previews. No ledger changes."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{CommandReceipt, Outbox}

  alias Ep.Finance.{
    Account,
    Book,
    CatalogueEntry,
    ChartImport,
    ChartImportCleanupWorker,
    JournalDraft,
    JournalState,
    JournalView,
    JournalWorker,
    Period,
    Periods,
    PeriodState,
    PeriodView,
    Setup,
    SetupState,
    SetupView,
    VatRule,
    VatRules
  }

  alias Ep.Projections.Control
  @command_type "FinanceJournalDraft:save"
  @fields ~w(id tenant_id book_id data validation contexts version actor_identity_id application_id)a
  @limit 9_000_000_000_000

  def get(principal, tid, bid, params \\ %{}) do
    scoped(principal, tid, bid, false, fn tid, bid, book, steward ->
      running!(tid)
      {latest, view} = registry(tid, bid)

      setup =
        case Setup.get(principal, tid, bid) do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end

      Periods.running!(tid)
      period_version = period_version(bid)
      period_view = Repo.get(PeriodView, bid)
      periods_ready = if(period_view, do: period_view.source_version, else: 0) == period_version
      drafts = if view, do: view.data["drafts"], else: []

      requested_id =
        if params["draft_id"] do
          case Ecto.UUID.cast(params["draft_id"]) do
            {:ok, id} -> id
            _ -> Repo.rollback(:not_found)
          end
        end

      selected = if requested_id, do: Enum.find(drafts, &(&1["id"] == requested_id))

      selected =
        if selected && params["version"] do
          case Enum.find(
                 selected["history"],
                 &(to_string(&1["version"]) == to_string(params["version"]))
               ) do
            nil -> nil
            h -> Map.put(h, "id", selected["id"])
          end
        else
          selected
        end

      requested_pending =
        if requested_id && !selected do
          protected = Repo.get_by(JournalDraft, id: requested_id, tenant_id: tid, book_id: bid)
          source = if view, do: view.source_version, else: 0

          unless protected && protected.version > source &&
                   (is_nil(params["version"]) ||
                      to_string(params["version"]) == to_string(protected.version)),
                 do: Repo.rollback(:not_found)

          true
        else
          false
        end

      contexts = contexts(book, setup.latest_version, period_version)

      %{
        work_rows_enabled: true,
        historical: !is_nil(params["version"]),
        tenant_id: tid,
        book_id: bid,
        book_name: book.name,
        book_status: book.status,
        base_currency: book.base_currency,
        accounting_authority: book.accounting_authority,
        source_version: if(view, do: view.source_version, else: 0),
        latest_version: latest,
        status:
          if(
            if(view, do: view.source_version, else: 0) == latest && setup.status == "ready" &&
              periods_ready,
            do: "ready",
            else: "pending"
          ),
        contexts: contexts,
        permissions: %{prepare: steward},
        accounts:
          setup.accounts
          |> Setup.normalize_accounts()
          |> Enum.filter(&(&1["kind"] == "posting"))
          |> Enum.map(fn account ->
            account = Ep.Finance.Catalogues.labels(account, setup.catalogue_entries)

            account
            |> Map.take(
              ~w(id number name active vat_entry_id vat_basis vat_code category vat_label category_label)
            )
          end),
        vat_entries: Enum.filter(setup.catalogue_entries, &(&1["kind"] == "vat" && &1["active"])),
        drafts:
          Enum.map(drafts, fn d ->
            Map.take(d, ~w(id data version validation contexts actor_identity_id application_id))
            |> Map.put(
              "history",
              Enum.map(
                d["history"],
                &Map.take(&1, ~w(version accepted_at actor_identity_id application_id))
              )
            )
          end),
        requested_draft_pending: requested_pending,
        selected: selected,
        validation_stale: selected && selected["contexts"] != contexts
      }
    end)
  end

  def review(principal, tid, bid, params, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, book, _ ->
      current = ready!(tid, bid, book)

      unless is_map(params) &&
               Enum.sort(Map.keys(params)) ==
                 ~w(contexts data draft_id expected_draft_version expected_version) &&
               is_integer(params["expected_version"]) &&
               params["expected_version"] == current["journal_version"] &&
               params["contexts"] === current["contexts"],
             do: Repo.rollback(:version_conflict)

      old =
        if params["draft_id"] not in [nil, ""],
          do:
            Repo.get_by(JournalDraft, tenant_id: tid, book_id: bid, id: uuid!(params["draft_id"])) ||
              Repo.rollback(:not_found)

      if old &&
           (!is_integer(params["expected_draft_version"]) ||
              old.version != params["expected_draft_version"]),
         do: Repo.rollback(:version_conflict)

      if !old && params["expected_draft_version"] != nil, do: Repo.rollback(:invalid_journal)

      if !old && Repo.aggregate(from(j in JournalDraft, where: j.book_id == ^bid), :count) >= 100,
        do: Repo.rollback(:journal_limit)

      if old && old.data["rows"] &&
           (!is_map(params["data"]) || !Map.has_key?(params["data"], "rows")),
         do: Repo.rollback(:invalid_journal)

      data = data!(tid, bid, params["data"])
      validation = validate(tid, bid, data)

      plan = %{
        "draft_id" => old && old.id,
        "expected_draft_version" => old && old.version,
        "data" => data,
        "validation" => validation,
        "contexts" => current["contexts"],
        "before" => if(old, do: snapshot(old))
      }

      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      row =
        Repo.insert!(%ChartImport{
          tenant_id: tid,
          book_id: bid,
          identity_id: principal.identity_id,
          application_id: app,
          expires_at: expires,
          data: %{
            "purpose" => "journal_draft",
            "expected_version" => current["journal_version"],
            "plan" => plan,
            "digest" =>
              Base.encode16(
                :crypto.hash(
                  :sha256,
                  :erlang.term_to_binary({tid, bid, principal.identity_id, app, current, plan})
                )
              )
          }
        })

      Oban.insert!(
        ChartImportCleanupWorker.new(%{import_id: row.id, tenant_id: tid}, scheduled_at: expires)
      )

      present(row)
    end)
  end

  def preview_row(principal, tid, bid, p) do
    scoped(principal, tid, bid, false, fn tid, bid, book, _ ->
      current = ready!(tid, bid, book)

      draft =
        Repo.get_by(JournalDraft, id: uuid!(p["draft_id"]), tenant_id: tid, book_id: bid) ||
          Repo.rollback(:not_found)

      unless p["expected_draft_version"] === draft.version &&
               p["contexts"] === current["contexts"],
             do: Repo.rollback(:version_conflict)

      data =
        draft.data
        |> Map.take(~w(name posting_date reference))
        |> Map.put("rows", [p["row"]])
        |> then(&data!(tid, bid, &1))

      %{validation: validate(tid, bid, data), row: hd(data["rows"])}
    end)
  end

  def get_review(principal, tid, bid, id, app \\ "internal"),
    do:
      scoped(principal, tid, bid, true, fn tid, bid, _, _ ->
        present(review!(principal.identity_id, tid, bid, id, app))
      end)

  def accept(principal, tid, bid, params, key, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid, book, _ ->
      unless is_map(params) &&
               Enum.sort(Map.keys(params)) == ~w(digest expected_version review_id) &&
               is_integer(params["expected_version"]) && is_binary(key) &&
               Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
             do: Repo.rollback(:invalid_journal)

      Events.lock!("command:" <> principal.identity_id <> ":" <> @command_type <> ":" <> key)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, params, app}))

      case Repo.get_by(CommandReceipt,
             identity_id: principal.identity_id,
             command_type: @command_type,
             idempotency_key: key
           ) do
        %{fingerprint: ^fingerprint, result: result} ->
          Map.put(result, "replayed", true)

        nil ->
          current = ready!(tid, bid, book)
          review = review!(principal.identity_id, tid, bid, params["review_id"], app)
          if review.accepted_command_id, do: Repo.rollback(:review_already_accepted)
          unless review.data["digest"] == params["digest"], do: Repo.rollback(:digest_conflict)

          unless current["journal_version"] == params["expected_version"] &&
                   review.data["expected_version"] == params["expected_version"] &&
                   review.data["plan"]["contexts"] === current["contexts"],
                 do: Repo.rollback(:version_conflict)

          plan = review.data["plan"]

          old =
            if plan["draft_id"],
              do:
                Repo.get_by(JournalDraft, tenant_id: tid, book_id: bid, id: plan["draft_id"]) ||
                  Repo.rollback(:not_found)

          if old && old.version != plan["expected_draft_version"],
            do: Repo.rollback(:version_conflict)

          # These snapshots are preparation evidence only; future posting must independently revalidate all guards.
          unless validate(tid, bid, plan["data"]) == plan["validation"],
            do: Repo.rollback(:version_conflict)

          cid = Ecto.UUID.generate()
          eid = Ecto.UUID.generate()
          version = current["journal_version"] + 1

          numbered_data =
            Ep.Finance.JournalRows.assign!(tid, bid, if(old, do: old.id, else: eid), plan["data"])

          attrs = %{
            data: numbered_data,
            validation:
              Ep.Finance.JournalPostingPreview.numbered(plan["validation"], numbered_data),
            contexts: plan["contexts"],
            version: version,
            actor_identity_id: principal.identity_id,
            application_id: app
          }

          draft =
            if old,
              do: Repo.update!(Ecto.Changeset.change(old, attrs)),
              else:
                Repo.insert!(
                  struct!(
                    JournalDraft,
                    Map.merge(attrs, %{id: eid, tenant_id: tid, book_id: bid})
                  )
                )

          ensure_control!(tid)

          [event] =
            Events.append!(
              %{
                id: eid,
                scope: "tenant",
                scope_key: "tenant:" <> tid,
                tenant_id: tid,
                stream_type: "finance_journals",
                stream_id: bid,
                actor_identity_id: principal.identity_id,
                command_id: cid,
                correlation_id: cid
              },
              [
                {if(old, do: "JournalDraftRevised", else: "JournalDraftCreated"),
                 %{"draft" => snapshot(draft)}}
              ]
            )

          unless event.stream_version == version, do: Repo.rollback(:version_conflict)

          state =
            Repo.get(JournalState, bid) ||
              Repo.insert!(%JournalState{book_id: bid, tenant_id: tid})

          Repo.update!(Ecto.Changeset.change(state, version: version))
          Repo.update!(Ecto.Changeset.change(review, accepted_command_id: cid))
          Repo.insert!(%Outbox{tenant_id: tid, event_id: eid})
          Oban.insert!(JournalWorker.new(%{tenant_id: tid}))

          result = %{
            "command_id" => cid,
            "draft_id" => draft.id,
            "tenant_id" => tid,
            "book_id" => bid,
            "stream_version" => version,
            "event_ids" => [eid]
          }

          Repo.insert!(%CommandReceipt{
            id: cid,
            identity_id: principal.identity_id,
            command_type: @command_type,
            idempotency_key: key,
            fingerprint: fingerprint,
            result: result
          })

          Map.put(result, "replayed", false)

        _ ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
  end

  defp data!(tid, bid, %{"rows" => _} = p) do
    unless Enum.sort(Map.keys(p)) == ~w(name posting_date reference rows),
      do: Repo.rollback(:invalid_journal)

    base = data!(tid, bid, p |> Map.delete("rows") |> Map.put("lines", []))
    {rows, lines} = Ep.Finance.JournalRows.expand!(tid, bid, Map.put(base, "rows", p["rows"]))
    normalized = line_data!(tid, bid, Map.put(base, "lines", lines), 200)
    Map.put(normalized, "rows", rows)
  end

  defp data!(tid, bid, p), do: line_data!(tid, bid, p, 100)

  defp line_data!(tid, bid, p, limit) do
    unless is_map(p) && Enum.sort(Map.keys(p)) == ~w(lines name posting_date reference) &&
             is_list(p["lines"]) && length(p["lines"]) in 0..limit,
           do: Repo.rollback(:invalid_journal)

    date =
      case p["posting_date"] do
        value when is_binary(value) ->
          case Date.from_iso8601(value) do
            {:ok, %Date{year: y} = d} when y >= 1 ->
              if(Date.to_iso8601(d) == value, do: d, else: Repo.rollback(:invalid_journal))

            _ ->
              Repo.rollback(:invalid_journal)
          end

        _ ->
          Repo.rollback(:invalid_journal)
      end

    lines =
      Enum.map(p["lines"], fn l ->
        unless is_map(l) &&
                 Enum.sort(Map.keys(l)) ==
                   ~w(account_id assessed_vat_minor credit_minor debit_minor id net_minor reference vat_entry_id),
               do: Repo.rollback(:invalid_journal)

        for field <- ~w(debit_minor credit_minor),
            do:
              unless(is_integer(l[field]) && l[field] in 0..@limit,
                do: Repo.rollback(:invalid_amount)
              )

        for field <- ~w(net_minor assessed_vat_minor),
            do:
              unless(is_nil(l[field]) || (is_integer(l[field]) && abs(l[field]) <= @limit),
                do: Repo.rollback(:invalid_amount)
              )

        aid = if l["account_id"] not in [nil, ""], do: uuid!(l["account_id"])

        if aid && !Repo.get_by(Account, tenant_id: tid, book_id: bid, id: aid),
          do: Repo.rollback(:invalid_account_reference)

        vat = if l["vat_entry_id"] not in [nil, ""], do: uuid!(l["vat_entry_id"])

        if vat && !Repo.get_by(CatalogueEntry, tenant_id: tid, book_id: bid, id: vat, kind: "vat"),
          do: Repo.rollback(:invalid_vat_reference)

        if !vat && (l["net_minor"] != nil || l["assessed_vat_minor"] != nil),
          do: Repo.rollback(:invalid_journal)

        Map.merge(l, %{
          "id" => if(l["id"] in [nil, ""], do: Ecto.UUID.generate(), else: uuid!(l["id"])),
          "account_id" => aid,
          "vat_entry_id" => vat,
          "reference" => text!(l["reference"], 120, true)
        })
      end)

    unless length(Enum.uniq_by(lines, & &1["id"])) == length(lines),
      do: Repo.rollback(:invalid_journal)

    %{
      "name" => text!(p["name"], 120, false),
      "reference" => text!(p["reference"], 120, true),
      "posting_date" => Date.to_iso8601(date),
      "lines" => lines
    }
  end

  defp validate(tid, bid, data) do
    date = Date.from_iso8601!(data["posting_date"])

    period =
      Repo.one(
        from p in Period,
          where:
            p.tenant_id == ^tid and p.book_id == ^bid and p.start_date <= ^date and
              p.end_date >= ^date,
          lock: "FOR SHARE"
      )

    lines =
      Enum.with_index(data["lines"], 1)
      |> Enum.map(fn {l, index} ->
        a =
          if l["account_id"],
            do: Repo.get_by(Account, tenant_id: tid, book_id: bid, id: l["account_id"])

        errors =
          cond do
            !a -> ["account_required"]
            a.kind != "posting" -> ["posting_account_required"]
            a.retired || !a.active -> ["account_inactive_or_retired"]
            true -> []
          end

        errors =
          errors ++
            if(l["debit_minor"] > 0 == l["credit_minor"] > 0,
              do: ["choose_one_nonzero_side"],
              else: []
            )

        vat =
          if l["vat_entry_id"] do
            entry =
              Repo.get_by(CatalogueEntry,
                tenant_id: tid,
                book_id: bid,
                id: l["vat_entry_id"],
                kind: "vat"
              )

            rule =
              Repo.one(
                from r in VatRule,
                  where:
                    r.tenant_id == ^tid and r.book_id == ^bid and
                      r.vat_entry_id == ^l["vat_entry_id"] and r.active and r.valid_from <= ^date and
                      (is_nil(r.valid_until) or r.valid_until >= ^date),
                  lock: "FOR SHARE"
              )

            cond do
              !entry || !entry.active ->
                %{"error" => "inactive_vat_entry"}

              !rule ->
                %{"error" => "vat_rule_missing"}

              true ->
                row =
                  Enum.find(data["rows"] || [], fn row ->
                    row["debit_line_id"] == l["id"] || row["credit_line_id"] == l["id"]
                  end)

                quote =
                  if row && row["amount_basis"] == "gross" && rule.direction in ~w(input output),
                    do: VatRules.calculate_gross(rule, date, l["net_minor"]),
                    else: VatRules.calculate(rule, date, l["net_minor"], l["assessed_vat_minor"])

                quote =
                  if row && is_nil(row["amount_basis"]),
                    do: {:error, :vat_basis_required},
                    else: quote

                case quote do
                  {:ok, q} ->
                    q = q |> Jason.encode!() |> Jason.decode!() |> Map.put("code", entry.code)

                    if row do
                      source_side =
                        if row["debit_line_id"] == l["id"], do: "debit", else: "credit"

                      signed_vat =
                        case rule.direction do
                          "input" -> q["amounts"]["deductible_vat"]
                          "output" -> -q["amounts"]["vat"]
                          _ -> q["amounts"]["vat"]
                        end

                      q
                      |> Map.put("posting_vat_minor", signed_vat)
                      |> Map.put("posting_direction", rule.direction)
                      |> Map.put("posting_source_side", source_side)
                    else
                      q
                    end

                  {:error, reason} ->
                    %{"error" => Atom.to_string(reason)}
                end
            end
          end

        errors = errors ++ if(vat && vat["error"], do: [vat["error"]], else: [])

        explicitly_disabled =
          Enum.any?(data["rows"] || [], fn row ->
            row["vat_enabled"] == false &&
              l["id"] in [row["debit_line_id"], row["credit_line_id"]]
          end)

        warnings =
          if a && a.vat_entry_id && !l["vat_entry_id"] && !explicitly_disabled,
            do: ["account_vat_not_selected"],
            else: []

        %{
          "id" => l["id"],
          "line" => index,
          "account" =>
            if(a,
              do:
                a
                |> Map.take(~w(id number name kind active retired version vat_entry_id)a)
                |> stringify()
            ),
          "vat" => vat,
          "errors" => errors,
          "warnings" => warnings
        }
      end)

    debit = Enum.sum(Enum.map(data["lines"], & &1["debit_minor"]))
    credit = Enum.sum(Enum.map(data["lines"], & &1["credit_minor"]))

    errors =
      if(debit != credit, do: ["journal_unbalanced"], else: []) ++
        if(debit == 0 || length(data["lines"]) < 2, do: ["two_nonzero_lines_required"], else: []) ++
        if !period || period.status != "open", do: ["period_not_open"], else: []

    warnings = Enum.flat_map(lines, & &1["warnings"])

    %{
      "debit_minor" => debit,
      "credit_minor" => credit,
      "difference_minor" => debit - credit,
      "balanced" => debit == credit,
      "errors" => errors,
      "lines" => lines,
      "status" =>
        if(errors == [] && Enum.all?(lines, &(&1["errors"] == [])) && warnings == [],
          do: "prepared",
          else: "needs_attention"
        ),
      "period" =>
        if(period,
          do:
            period
            |> Map.take(~w(id name status version start_date end_date)a)
            |> stringify()
            |> Jason.encode!()
            |> Jason.decode!()
        ),
      "vat_complete" => Enum.all?(lines, &(!&1["vat"] || !&1["vat"]["error"])),
      "reporting" =>
        Enum.reduce(lines, %{}, fn line, acc ->
          Enum.reduce((line["vat"] || %{})["reporting"] || %{}, acc, fn {box, value}, acc ->
            Map.update(acc, box, value, &(&1 + value))
          end)
        end)
    }
    |> then(fn validation ->
      preview = Ep.Finance.JournalPostingPreview.build(tid, bid, data, validation)
      validation = Map.put(validation, "posting_preview", preview)

      if is_list(data["rows"]) do
        errors =
          Enum.uniq(
            (validation["errors"] -- ["journal_unbalanced", "two_nonzero_lines_required"]) ++
              preview["errors"]
          )

        validation
        |> Map.merge(Map.take(preview, ~w(debit_minor credit_minor difference_minor balanced)))
        |> Map.put("errors", errors)
        |> Map.put(
          "status",
          if(errors == [] && warnings == [], do: "prepared", else: "needs_attention")
        )
      else
        validation
      end
    end)
  end

  def running!(tid) do
    control =
      Repo.one(
        from c in Control,
          where: c.tenant_id == ^tid and c.name == "finance_journals",
          lock: "FOR SHARE"
      )

    if (control && control.state != "running") ||
         (!control && Repo.exists?(from s in JournalState, where: s.tenant_id == ^tid)),
       do: Repo.rollback(:view_stopped)
  end

  defp ensure_control!(tid) do
    Events.lock!("finance-journal-control:" <> tid)

    unless Repo.get_by(Control, tenant_id: tid, name: "finance_journals"),
      do: Repo.insert!(%Control{tenant_id: tid, name: "finance_journals"})
  end

  defp scoped(principal, tid, bid, write, fun) do
    with {:ok, tid} <- Ecto.UUID.cast(tid), {:ok, bid} <- Ecto.UUID.cast(bid) do
      Repo.transaction(fn ->
        {_book, _, steward} = Setup.authorize!(principal, tid, bid)

        book =
          Repo.one!(
            from b in Book, where: b.tenant_id == ^tid and b.id == ^bid, lock: "FOR SHARE"
          )

        if write && !steward, do: Repo.rollback(:not_found)
        Events.lock!("finance-journals:" <> bid)
        fun.(tid, bid, book, steward)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp ready!(tid, bid, book) do
    running!(tid)
    Setup.running!(tid)
    Periods.running!(tid)
    Events.lock!("finance-periods:" <> bid)
    {latest, view} = registry(tid, bid)
    setup = Repo.get(SetupState, bid)
    setup_version = if setup, do: setup.version, else: 0
    setup_view = Repo.get(SetupView, bid)
    pv = Repo.get(PeriodView, bid)
    period_version = period_version(bid)

    if if(view, do: view.source_version, else: 0) != latest ||
         if(setup_view, do: setup_view.source_version, else: 0) != setup_version ||
         if(pv, do: pv.source_version, else: 0) != period_version,
       do: Repo.rollback(:view_pending)

    %{"journal_version" => latest, "contexts" => contexts(book, setup_version, period_version)}
  end

  defp registry(_tid, bid) do
    state = Repo.get(JournalState, bid)
    {if(state, do: state.version, else: 0), Repo.get(JournalView, bid)}
  end

  defp period_version(bid) do
    state = Repo.get(PeriodState, bid)
    if state, do: state.version, else: 0
  end

  defp contexts(book, setup_version, period_version),
    do: %{
      "setup_version" => setup_version,
      "period_version" => period_version,
      "book_version" => book.version,
      "base_currency" => book.base_currency,
      "accounting_authority" => book.accounting_authority
    }

  defp snapshot(d), do: d |> Map.take(@fields) |> stringify()

  defp review!(actor, tid, bid, id, app) do
    r =
      Repo.get_by(ChartImport,
        id: uuid!(id),
        tenant_id: tid,
        book_id: bid,
        identity_id: actor,
        application_id: app
      ) || Repo.rollback(:not_found)

    unless r.data["purpose"] == "journal_draft", do: Repo.rollback(:not_found)

    if DateTime.compare(r.expires_at, DateTime.utc_now()) != :gt,
      do: Repo.rollback(:review_expired)

    r
  end

  defp present(r),
    do: %{
      review_id: r.id,
      expected_version: r.data["expected_version"],
      digest: r.data["digest"],
      plan: r.data["plan"],
      expires_at: DateTime.to_iso8601(r.expires_at),
      accepted_command_id: r.accepted_command_id
    }

  defp uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_journal)
    end
  end

  defp text!(s, max, blank) do
    unless is_binary(s) && String.length(String.trim(s)) <= max && (blank || String.trim(s) != "") &&
             !Regex.match?(~r/[\p{Cc}\p{Cf}]/u, s),
           do: Repo.rollback(:invalid_journal)

    String.trim(s)
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
end
