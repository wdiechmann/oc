defmodule Ep.Finance.Reports do
  @moduledoc "Reviewed, versioned book-local report configuration. Test previews never post or persist balances."
  import Ecto.Query
  alias Ep.Repo

  alias Ep.Finance.{
    Account,
    ChartImport,
    ChartImportCleanupWorker,
    Formula,
    FormulaPreview,
    ReportDefinition,
    Setup,
    SetupState,
    SetupView
  }

  @fields ~w(id tenant_id book_id name active definition reserved_codes version actor_identity_id application_id)a
  @events ~w(ReportDefinitionCreated ReportDefinitionRevised)
  @limit 9_000_000_000_000

  def get(principal, tid, bid, params \\ %{}) do
    with {:ok, data} <- Setup.get(principal, tid, bid) do
      accounts =
        Setup.normalize_accounts(data.accounts) |> Enum.filter(&(&1["kind"] == "posting"))

      preset = Ep.Finance.ReportPresets.ytd(accounts, data.source_version)

      reports =
        if Enum.any?(data.reports, &(&1["name"] == preset["name"])),
          do: data.reports,
          else: [preset | data.reports]

      selected =
        if params["report_id"], do: Enum.find(reports, &(&1["id"] == params["report_id"]))

      selected =
        if selected && params["version"] && !selected["builtin"] do
          Enum.find(
            selected["history"] || [],
            &(to_string(&1["version"]) == to_string(params["version"]))
          )
          |> case do
            nil -> nil
            revision -> Map.merge(revision, %{"id" => selected["id"]})
          end
        else
          selected
        end

      if (selected && selected["builtin"] && params["version"] &&
            to_string(params["version"]) != "1") || (params["report_id"] && !selected) do
        {:error, :not_found}
      else
        accounts =
          Setup.normalize_accounts(data.accounts) |> Enum.filter(&(&1["kind"] == "posting"))

        {:ok,
         Map.take(data, [
           :tenant_id,
           :book_id,
           :book_name,
           :status,
           :source_version,
           :latest_version,
           :permissions
         ])
         |> Map.merge(%{
           reports:
             Enum.map(reports, fn r ->
               Map.drop(r, ~w(definition reserved_codes))
               |> Map.update!("history", fn hs ->
                 Enum.map(hs, &Map.drop(&1, ~w(definition reserved_codes)))
               end)
             end),
           accounts: Enum.map(accounts, &Map.take(&1, ~w(id number name active version))),
           selected: selected,
           coverage:
             if(selected,
               do: coverage(selected["definition"]["lines"], selected["definition"]["accounts"])
             ),
           current_coverage: if(selected, do: coverage(selected["definition"]["lines"], accounts))
         })}
      end
    end
  end

  def snapshot(bid),
    do:
      Repo.all(from r in ReportDefinition, where: r.book_id == ^bid, order_by: r.id)
      |> Enum.map(&Map.take(&1, @fields))

  def review(principal, tid, bid, params, app \\ "internal") do
    scoped(principal, tid, bid, fn tid, bid, _book ->
      version = ready!(tid, bid)

      unless is_map(params) &&
               Enum.sort(Map.keys(params)) ==
                 ~w(active expected_report_version expected_version lines name report_id) &&
               is_integer(params["expected_version"]) && params["expected_version"] == version,
             do: Repo.rollback(:version_conflict)

      old =
        if params["report_id"] not in [nil, ""],
          do:
            Repo.get_by(ReportDefinition,
              tenant_id: tid,
              book_id: bid,
              id: uuid!(params["report_id"])
            ) || Repo.rollback(:not_found)

      if old &&
           (!is_integer(params["expected_report_version"]) ||
              old.version != params["expected_report_version"]),
         do: Repo.rollback(:version_conflict)

      if !old && params["expected_report_version"] != nil, do: Repo.rollback(:invalid_report)

      if !old &&
           Repo.aggregate(from(r in ReportDefinition, where: r.book_id == ^bid), :count) >= 20,
         do: Repo.rollback(:report_limit)

      name = name!(params["name"])
      unless is_boolean(params["active"]), do: Repo.rollback(:invalid_report)

      accounts =
        Repo.all(
          from a in Account,
            where:
              a.tenant_id == ^tid and a.book_id == ^bid and a.kind == "posting" and not a.retired,
            order_by: [a.position, a.id]
        )
        |> Enum.map(fn a -> a |> Map.take(~w(id number name active version)a) |> stringify() end)

      if length(accounts) > 2000, do: Repo.rollback(:chart_too_large)
      {lines, reserved} = lines!(params["lines"], accounts, old)

      plan = %{
        "report_id" => old && old.id,
        "expected_report_version" => old && old.version,
        "name" => name,
        "active" => params["active"],
        "definition" => %{"lines" => lines, "accounts" => accounts, "chart_version" => version},
        "reserved_codes" => reserved,
        "before" => if(old, do: old |> Map.take([:name, :active, :definition]) |> stringify()),
        "coverage" => coverage(lines, accounts)
      }

      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      review =
        Repo.insert!(%ChartImport{
          tenant_id: tid,
          book_id: bid,
          identity_id: principal.identity_id,
          application_id: app,
          expires_at: expires,
          data: %{
            "purpose" => "report_definition",
            "expected_version" => version,
            "plan" => plan,
            "digest" =>
              Base.encode16(
                :crypto.hash(
                  :sha256,
                  :erlang.term_to_binary({tid, bid, principal.identity_id, app, version, plan})
                )
              )
          }
        })

      Oban.insert!(
        ChartImportCleanupWorker.new(%{import_id: review.id, tenant_id: tid},
          scheduled_at: expires
        )
      )

      present(review)
    end)
  end

  def get_review(principal, tid, bid, id, app \\ "internal"),
    do:
      scoped(principal, tid, bid, fn tid, bid, _ ->
        present(review!(principal.identity_id, tid, bid, id, app))
      end)

  def mutate!(tid, bid, params, eid, version, actor, app) do
    unless Enum.sort(Map.keys(params)) == ~w(digest expected_version review_id),
      do: Repo.rollback(:invalid_report)

    unless ready!(tid, bid) == version - 1, do: Repo.rollback(:version_conflict)
    review = review!(actor, tid, bid, params["review_id"], app)
    if review.accepted_command_id, do: Repo.rollback(:review_already_accepted)
    unless review.data["digest"] == params["digest"], do: Repo.rollback(:digest_conflict)
    unless review.data["expected_version"] == version - 1, do: Repo.rollback(:version_conflict)
    plan = review.data["plan"]

    old =
      if plan["report_id"],
        do:
          Repo.get_by(ReportDefinition, id: plan["report_id"], tenant_id: tid, book_id: bid) ||
            Repo.rollback(:not_found)

    if old && old.version != plan["expected_report_version"], do: Repo.rollback(:version_conflict)

    attrs = %{
      name: plan["name"],
      active: plan["active"],
      definition: plan["definition"],
      reserved_codes: plan["reserved_codes"],
      version: version,
      actor_identity_id: actor,
      application_id: app
    }

    if old,
      do: Repo.update!(Ecto.Changeset.change(old, attrs)),
      else:
        Repo.insert!(
          struct!(ReportDefinition, Map.merge(attrs, %{id: eid, tenant_id: tid, book_id: bid}))
        )

    if old, do: "ReportDefinitionRevised", else: "ReportDefinitionCreated"
  end

  def preview(principal, tid, bid, report_id, params) do
    with {:ok, data} <-
           get(principal, tid, bid, %{
             "report_id" => report_id,
             "version" => params["report_version"]
           }) do
      selected = data.selected

      cond do
        data.status != "ready" ->
          {:error, :view_pending}

        Enum.sort(Map.keys(params)) != ~w(balances report_version) ->
          {:error, :invalid_report}

        !is_integer(params["report_version"]) || params["report_version"] != selected["version"] ->
          {:error, :version_conflict}

        !valid_balances?(params["balances"], selected["definition"]["accounts"]) ->
          {:error, :invalid_balances}

        true ->
          {:ok,
           Map.merge(data, %{
             results: evaluate(selected["definition"], params["balances"]),
             balances: params["balances"]
           })}
      end
    end
  end

  @doc "Fiscal year-to-date balances from immutable posted journals, using a saved definition."
  def ytd(principal, tid, bid, params) do
    with {:ok, data} <- get(principal, tid, bid, Map.take(params, ~w(report_id version))),
         {:ok, cutoff} <- report_date(params["as_of"]) do
      cond do
        data.status != "ready" ->
          {:error, :view_pending}

        is_nil(data.selected) ->
          {:error, :not_found}

        true ->
          Repo.transaction(fn ->
            {book, _, _} = Setup.authorize!(principal, tid, bid)
            unless ready!(tid, bid) == data.latest_version, do: Repo.rollback(:view_pending)

            unless book.accounting_authority == "ep",
              do: Repo.rollback(:external_accounting_authority)

            month = book.fiscal_year_start_month
            year = cutoff.year - if(cutoff.month < month, do: 1, else: 0)
            start = Date.new!(year, month, 1)

            facts =
              Repo.all(
                from e in Ep.Events.Event,
                  join: d in Ep.Events.Details,
                  on: d.event_id == e.id,
                  where:
                    e.tenant_id == ^tid and e.stream_id == ^bid and
                      e.stream_type == "finance_journals" and e.event_type == "JournalPosted",
                  select: d.payload
              )

            zero = Map.new(data.selected["definition"]["accounts"], &{&1["id"], 0})

            {opening, movement, count} =
              Enum.reduce(facts, {zero, zero, 0}, fn fact, {opening, movement, count} ->
                date = Date.from_iso8601!(fact["draft"]["data"]["posting_date"])

                cond do
                  Date.compare(date, cutoff) == :gt ->
                    {opening, movement, count}

                  Date.compare(date, start) == :lt ->
                    {add_posting(opening, fact), movement, count}

                  true ->
                    {opening, add_posting(movement, fact), count + 1}
                end
              end)

            closing = Map.merge(opening, movement, fn _, a, b -> a + b end)
            definition = data.selected["definition"]

            Map.put(data, :ytd, %{
              start_date: Date.to_iso8601(start),
              as_of: Date.to_iso8601(cutoff),
              currency: book.base_currency,
              journal_count: count,
              opening: evaluate(definition, opening),
              movement: evaluate(definition, movement),
              closing: evaluate(definition, closing),
              balances: closing
            })
          end)
      end
    else
      {:error, :invalid_format} -> {:error, :invalid_report}
      {:error, :invalid_date} -> {:error, :invalid_report}
      error -> error
    end
  end

  defp report_date(nil), do: {:ok, Date.utc_today()}
  defp report_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp report_date(_), do: {:error, :invalid_report}

  defp add_posting(balances, fact) do
    Enum.reduce(fact["posting"]["accounts"], balances, fn row, values ->
      Map.update(values, row["account"]["id"], row["post_minor"], &(&1 + row["post_minor"]))
    end)
  end

  def evaluate(definition, balances) do
    lines = definition["lines"]
    accounts = Map.new(definition["accounts"], &{&1["id"], &1})

    mapped =
      Map.new(Enum.filter(lines, &(&1["kind"] == "mapping")), fn line ->
        missing = Enum.find(line["account_ids"], &(not Map.has_key?(balances, &1)))

        value =
          Enum.reduce(line["account_ids"], 0, &(&2 + Map.get(balances, &1, 0))) * line["sign"]

        result =
          cond do
            missing ->
              %{
                "status" => "error",
                "error" => "missing_balance",
                "related_account_id" => missing
              }

            abs(value) > @limit ->
              %{
                "status" => "error",
                "error" => "amount_out_of_range",
                "related_account_id" => nil
              }

            true ->
              %{
                "status" => "ok",
                "amount_minor" => value,
                "exact" => %{"numerator" => to_string(value), "denominator" => "1"},
                "inputs" =>
                  Enum.map(line["account_ids"], fn id ->
                    Map.put(accounts[id], "balance_minor", balances[id])
                  end),
                "references" => []
              }
          end

        {line["id"], Map.put(result, "account_id", line["id"])}
      end)

    rows =
      Enum.map(lines, fn l ->
        Map.merge(l, %{
          "number" => l["code"],
          "active" => true,
          "kind" =>
            %{"mapping" => "posting", "total" => "calculation", "header" => "header"}[l["kind"]]
        })
      end)

    values =
      for {id, %{"status" => "ok", "amount_minor" => value}} <- mapped, into: %{}, do: {id, value}

    totals =
      FormulaPreview.evaluate(rows, values)
      |> Jason.encode!()
      |> Jason.decode!()
      |> Map.new(fn result ->
        result =
          if result["error"] == "missing_balance" && mapped[result["related_account_id"]] do
            Map.merge(
              result,
              Map.take(mapped[result["related_account_id"]], ~w(error related_account_id))
            )
          else
            result
          end

        result =
          if result["status"] == "ok" do
            inputs =
              result["inputs"]
              |> Enum.flat_map(fn input -> mapped[input["account_id"]]["inputs"] end)
              |> Enum.uniq_by(& &1["id"])

            Map.put(result, "inputs", inputs)
          else
            result
          end

        {result["account_id"], result}
      end)

    for line <- lines, line["kind"] != "header", do: mapped[line["id"]] || totals[line["id"]]
  end

  def coverage(lines, accounts) do
    uses = for l <- lines, l["kind"] == "mapping", id <- l["account_ids"], do: {id, l["code"]}
    grouped = Enum.group_by(uses, &elem(&1, 0), &elem(&1, 1))

    %{
      "unavailable" => Map.keys(grouped) -- Enum.map(accounts, & &1["id"]),
      "unmapped" => Enum.filter(accounts, &(not Map.has_key?(grouped, &1["id"]))),
      "multiple" =>
        for(
          {id, codes} <- grouped,
          length(codes) > 1,
          do: %{"account_id" => id, "lines" => Enum.sort(codes)}
        ),
      "empty_lines" =>
        for(l <- lines, l["kind"] == "mapping" && l["account_ids"] == [], do: l["code"])
    }
  end

  def project(snapshot, old, event) do
    previous = Map.new((old || %{})["reports"] || [], &{&1["id"], &1})

    reports =
      Enum.map(snapshot["reports"] || [], fn report ->
        prior = previous[report["id"]]
        history = if prior, do: prior["history"] || [], else: []

        history =
          if report["version"] == event.stream_version &&
               (!prior || prior["version"] != report["version"]) do
            unless event.event_type in @events &&
                     report["actor_identity_id"] == event.actor_identity_id &&
                     report["tenant_id"] == event.tenant_id &&
                     report["book_id"] == event.stream_id,
                   do: Repo.rollback(:projection_scope)

            history ++
              [
                Map.drop(report, ~w(history tenant_id book_id))
                |> Map.merge(%{
                  "event_id" => event.id,
                  "event_type" => event.event_type,
                  "accepted_at" => DateTime.to_iso8601(event.inserted_at)
                })
              ]
          else
            history
          end

        Map.put(report, "history", history)
      end)

    Map.put(snapshot, "reports", reports)
  end

  defp lines!(list, accounts, old) do
    unless is_list(list) && length(list) in 1..2000, do: Repo.rollback(:invalid_report)
    allowed = MapSet.new(Enum.map(accounts, & &1["id"]))
    reserved = if old, do: old.reserved_codes, else: %{}
    prior = Map.new(if(old, do: old.definition["lines"], else: []), &{&1["id"], &1})

    lines =
      Enum.map(list, fn l ->
        unless is_map(l) &&
                 Enum.sort(Map.keys(l)) == ~w(account_ids code formula id kind name position sign),
               do: Repo.rollback(:invalid_report)

        id = if l["id"] in [nil, ""], do: Ecto.UUID.generate(), else: uuid!(l["id"])

        unless is_binary(l["code"]) && Regex.match?(~r/^[A-Za-z][A-Za-z0-9._-]{0,39}$/, l["code"]) &&
                 l["kind"] in ~w(header mapping total) && is_integer(l["position"]) &&
                 l["position"] in 1..2_000_000_000,
               do: Repo.rollback(:invalid_report)

        if reserved[l["code"]] && reserved[l["code"]] != id,
          do: Repo.rollback(:report_code_reserved)

        ids = l["account_ids"]

        unless is_list(ids) && length(ids) <= 2000 && length(Enum.uniq(ids)) == length(ids) &&
                 Enum.all?(ids, &MapSet.member?(allowed, &1)) && l["sign"] in [-1, 1],
               do: Repo.rollback(:invalid_report_reference)

        unless (l["kind"] == "mapping" || ids == []) &&
                 (l["kind"] == "total" || l["formula"] in [nil, ""]),
               do: Repo.rollback(:invalid_report)

        Map.merge(l, %{
          "id" => id,
          "name" => name!(l["name"]),
          "account_ids" => Enum.sort(ids),
          "formula" => if(l["kind"] == "total", do: l["formula"])
        })
      end)
      |> Enum.sort_by(&{&1["position"], &1["id"]})

    for field <- ~w(id code position),
        do:
          if(length(Enum.uniq_by(lines, & &1[field])) != length(lines),
            do: Repo.rollback(:invalid_report)
          )

    if Enum.sum(Enum.map(lines, &length(&1["account_ids"]))) > 4000,
      do: Repo.rollback(:report_limit)

    rows =
      Enum.map(lines, fn l ->
        %{
          id: l["id"],
          number: l["code"],
          kind:
            %{"mapping" => "posting", "total" => "calculation", "header" => "header"}[l["kind"]],
          formula: l["formula"],
          formula_refs: %{}
        }
      end)

    lines =
      Enum.map(lines, fn line ->
        refs =
          if line["kind"] == "total" do
            previous = prior[line["id"]]

            previous =
              if previous,
                do: %{formula: previous["formula"], formula_refs: previous["formula_refs"]}

            case Formula.references(line["formula"], rows, previous) do
              {:ok, refs} -> refs
              _ -> Repo.rollback(:invalid_formula)
            end
          else
            %{}
          end

        Map.put(line, "formula_refs", refs)
      end)

    unless Formula.acyclic?(
             Enum.map(lines, fn l ->
               %{
                 id: l["id"],
                 number: l["code"],
                 kind: if(l["kind"] == "header", do: "header", else: "posting"),
                 formula_refs: l["formula_refs"]
               }
             end)
           ),
           do: Repo.rollback(:invalid_formula)

    {lines, Enum.reduce(lines, reserved, &Map.put(&2, &1["code"], &1["id"]))}
  end

  defp valid_balances?(balances, accounts),
    do:
      is_map(balances) && map_size(balances) <= 2000 &&
        Enum.all?(balances, fn {id, value} ->
          Enum.any?(accounts, &(&1["id"] == id)) && is_integer(value) && abs(value) <= @limit
        end)

  defp name!(value) do
    unless is_binary(value) && String.length(String.trim(value)) in 1..120 &&
             !Regex.match?(~r/[\p{Cc}\p{Cf}]/u, value),
           do: Repo.rollback(:invalid_report)

    String.trim(value)
  end

  defp scoped(principal, tid, bid, fun) do
    with {:ok, tid} <- Ecto.UUID.cast(tid), {:ok, bid} <- Ecto.UUID.cast(bid) do
      Repo.transaction(fn ->
        {book, _, steward} = Setup.authorize!(principal, tid, bid)
        unless steward, do: Repo.rollback(:not_found)
        fun.(tid, bid, book)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp ready!(tid, bid) do
    Setup.running!(tid)
    state = Repo.get(SetupState, bid)
    view = Repo.get(SetupView, bid)
    version = if state, do: state.version, else: 0
    unless view && view.source_version == version, do: Repo.rollback(:view_pending)
    version
  end

  defp review!(actor, tid, bid, id, app) do
    r =
      Repo.get_by(ChartImport,
        id: uuid!(id),
        tenant_id: tid,
        book_id: bid,
        identity_id: actor,
        application_id: app
      ) || Repo.rollback(:not_found)

    unless r.data["purpose"] == "report_definition", do: Repo.rollback(:not_found)

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
      _ -> Repo.rollback(:not_found)
    end
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
end
