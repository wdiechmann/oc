defmodule Ep.Finance.Setup do
  @moduledoc "Book-local configuration authority and guarded setup commands. Never financial execution."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Finance.{Account, Binding, Book, SetupState, SetupView, SetupWorker, Steward}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Projections.Control

  @vat_codes ~w(none input output)
  @categories ~w(assets liabilities equity income expenses)
  @actions ~w(steward reopening_authority binding account_create account_revise)

  def get(principal, tid, bid) do
    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid) do
      Repo.transaction(fn ->
        {book, admin, steward} = authorize!(principal, tid, bid)
        running!(tid)
        state = Repo.get(SetupState, bid)
        latest = if state, do: state.version, else: 0
        row = Repo.get(SetupView, bid)
        source = if row, do: row.source_version, else: 0
        data = if row, do: row.data, else: %{"accounts" => [], "bindings" => []}

        %{
          tenant_id: tid,
          book_id: bid,
          book_name: book.name,
          status: if(source == latest, do: "ready", else: "pending"),
          source_version: source,
          latest_version: latest,
          permissions: %{assign_stewards: admin, configure: steward},
          accounts: data["accounts"],
          bindings: data["bindings"],
          stewards: if(admin, do: stewards(bid), else: []),
          candidates: if(admin, do: candidates(tid), else: []),
          occasions: if(steward, do: occasions(tid), else: [])
        }
      end)
    end
  end

  def accounts(principal, tid, bid, params \\ %{}) do
    with :ok <- valid_chart_params(params),
         {:ok, data} <- get(principal, tid, bid),
         {:ok, page} <- page_number(params["page"], 1),
         {:ok, size} <- page_number(params["per_page"], 50),
         :ok <- if(size <= 100, do: :ok, else: {:error, :invalid_setup}),
         true <-
           is_nil(params["source_version"]) or
             (data.status == "ready" and
                to_string(data.source_version) == to_string(params["source_version"])) do
      query = String.downcase(String.slice(to_string(params["q"] || ""), 0, 120))

      rows =
        normalize_accounts(data.accounts)
        |> Enum.filter(fn a ->
          String.contains?(String.downcase("#{a["number"]} #{a["name"]}"), query)
        end)

      focus = params["focus_id"]
      focused_index = if is_binary(focus), do: Enum.find_index(rows, &(&1["id"] == focus))
      page = if is_integer(focused_index), do: div(focused_index, size) + 1, else: page
      total = length(rows)
      pages = max(1, ceil(total / size))
      page = min(page, pages)

      {:ok,
       data
       |> Map.drop([:stewards, :candidates, :occasions, :bindings])
       |> Map.merge(%{
         accounts: Enum.slice(rows, (page - 1) * size, size),
         pagination: %{page: page, per_page: size, total_entries: total, total_pages: pages},
         options: %{vat_codes: @vat_codes, categories: @categories}
       })}
    else
      false -> {:error, :chart_changed}
      error -> error
    end
  end

  def normalize_accounts(rows) do
    rows
    |> Enum.sort_by(&{&1["position"] || 0, &1["number"] || "", &1["id"]})
    |> Enum.with_index(1)
    |> Enum.map(fn {a, index} ->
      kind =
        case a["kind"] do
          "heading" -> "header"
          "total" -> "calculation"
          other -> other
        end

      Map.merge(
        %{"vat_code" => nil, "category" => nil, "formula" => nil, "position" => index * 100},
        a
      )
      |> Map.put("kind", kind)
      |> Map.put("number", if(kind == "posting", do: a["number"], else: nil))
    end)
    |> Enum.sort_by(&{&1["position"], &1["id"]})
  end

  defp valid_chart_params(params) when is_map(params) do
    valid =
      Enum.all?(params, fn
        {"q", value} ->
          is_binary(value)

        {key, value} when key in ~w(page per_page source_version) ->
          (is_integer(value) && value >= 0) ||
            (is_binary(value) && Regex.match?(~r/^\d{1,10}$/, value))

        {"focus_id", value} ->
          match?({:ok, _}, Ecto.UUID.cast(value))

        _ ->
          false
      end)

    if valid, do: :ok, else: {:error, :invalid_setup}
  end

  defp valid_chart_params(_), do: {:error, :invalid_setup}

  defp page_number(nil, default), do: {:ok, default}

  defp page_number(value, _) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_setup}
    end
  end

  def command(principal, tid, bid, action, params, key, application_id \\ "internal") do
    with {:ok, tid} <- uuid(tid),
         {:ok, bid} <- uuid(bid),
         true <- action in @actions,
         true <- is_map(params),
         true <- is_binary(key) and Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key) do
      Repo.transaction(fn ->
        {_book, admin, steward} = authorize!(principal, tid, bid)

        unless if(action in ~w(steward reopening_authority), do: admin, else: steward),
          do: Repo.rollback(:not_found)

        # All role changes and commands use this same book lock; authority cannot go stale.
        type = "FinanceSetup:" <> action
        Events.lock!("command:" <> principal.identity_id <> ":" <> type <> ":" <> key)
        fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, params}))

        case Repo.get_by(CommandReceipt,
               identity_id: principal.identity_id,
               command_type: type,
               idempotency_key: key
             ) do
          nil ->
            state =
              Repo.get(SetupState, bid) || Repo.insert!(%SetupState{book_id: bid, tenant_id: tid})

            unless is_integer(params["expected_version"]) &&
                     params["expected_version"] == state.version,
                   do: Repo.rollback(:version_conflict)

            cid = Ecto.UUID.generate()
            event_id = Ecto.UUID.generate()

            event_type =
              mutate!(
                tid,
                bid,
                action,
                params,
                event_id,
                state.version + 1,
                principal.identity_id,
                application_id
              )

            ensure_control!(tid)

            [event] =
              Events.append!(
                %{
                  id: event_id,
                  scope: "tenant",
                  scope_key: "tenant:" <> tid,
                  tenant_id: tid,
                  stream_type: "finance_setup",
                  stream_id: bid,
                  actor_identity_id: principal.identity_id,
                  command_id: cid,
                  correlation_id: cid
                },
                [
                  {event_type,
                   %{
                     "book_id" => bid,
                     "tenant_id" => tid,
                     "application_id" => application_id,
                     "change" =>
                       Map.drop(params, ["expected_version", "expected_account_version"]),
                     "setup" => snapshot(bid)
                   }}
                ]
              )

            Repo.update!(Ecto.Changeset.change(state, version: event.stream_version))
            Repo.insert!(%Outbox{tenant_id: tid, event_id: event.id})
            Oban.insert!(SetupWorker.new(%{tenant_id: tid}))

            result = %{
              "command_id" => cid,
              "tenant_id" => tid,
              "book_id" => bid,
              "event_ids" => [event.id],
              "stream_version" => event.stream_version
            }

            Repo.insert!(%CommandReceipt{
              id: cid,
              identity_id: principal.identity_id,
              command_type: type,
              idempotency_key: key,
              fingerprint: fingerprint,
              result: result
            })

            Map.put(result, "replayed", false)

          %{fingerprint: ^fingerprint, result: result} ->
            Map.put(result, "replayed", true)

          _ ->
            Repo.rollback(:idempotency_conflict)
        end
      end)
    else
      _ -> {:error, :invalid_setup}
    end
  end

  @doc false
  def authorize!(principal, tid, bid) do
    Auth.lock_principal!(principal)

    tenant =
      Repo.one(
        from t in Ep.Tenancy.Tenant,
          where: t.id == ^tid and t.status == "active",
          lock: "FOR SHARE"
      )

    unless tenant, do: Repo.rollback(:not_found)

    admin =
      Repo.one(
        from a in Ep.Tenancy.Access,
          where:
            a.tenant_id == ^tid and a.identity_id == ^principal.identity_id and
              a.role == "tenant_admin" and a.status == "active",
          lock: "FOR SHARE"
      )

    Events.lock!("finance-setup:" <> bid)
    book = Repo.get_by(Book, tenant_id: tid, id: bid) || Repo.rollback(:not_found)

    steward =
      Repo.get_by(Steward,
        tenant_id: tid,
        book_id: bid,
        identity_id: principal.identity_id,
        active: true
      )

    unless admin || steward, do: Repo.rollback(:not_found)
    {book, not is_nil(admin), not is_nil(steward)}
  end

  defp mutate!(tid, bid, "steward", p, _eid, _version, _actor, _app) do
    fields!(p, ~w(identity_id active expected_version))
    identity = uuid!(p["identity_id"])
    active = boolean!(p["active"])

    Repo.one(
      from i in Ep.Auth.Identity,
        where:
          i.id == ^identity and
            (not (^active) or (i.status == "active" and not is_nil(i.verified_at))),
        lock: "FOR SHARE"
    ) || Repo.rollback(:invalid_setup)

    case Repo.get_by(Steward, book_id: bid, identity_id: identity) do
      nil ->
        Repo.insert!(%Steward{
          tenant_id: tid,
          book_id: bid,
          identity_id: identity,
          active: active
        })

      row ->
        Repo.update!(
          Ecto.Changeset.change(row,
            active: active,
            can_reopen_periods: active && row.can_reopen_periods
          )
        )
    end

    if active, do: "FinanceStewardAssigned", else: "FinanceStewardRevoked"
  end

  defp mutate!(tid, bid, "reopening_authority", p, _eid, _version, _actor, _app) do
    fields!(p, ~w(identity_id allow expected_version))
    identity = uuid!(p["identity_id"])
    allow = boolean!(p["allow"])

    Repo.one(
      from i in Ep.Auth.Identity,
        where:
          i.id == ^identity and
            (not (^allow) or (i.status == "active" and not is_nil(i.verified_at))),
        lock: "FOR SHARE"
    ) || Repo.rollback(:not_found)

    row =
      Repo.get_by(Steward, tenant_id: tid, book_id: bid, identity_id: identity, active: true) ||
        Repo.rollback(:not_found)

    Repo.update!(Ecto.Changeset.change(row, can_reopen_periods: allow))
    if allow, do: "PeriodReopeningAuthorized", else: "PeriodReopeningRevoked"
  end

  defp mutate!(tid, bid, "binding", p, _eid, _version, _actor, _app) do
    fields!(p, ~w(occasion_id active expected_version))
    oid = uuid!(p["occasion_id"])
    active = boolean!(p["active"])
    Events.lock!("finance-binding:" <> tid <> ":" <> oid)

    Repo.one(
      from o in Ep.Occasions.Occasion,
        where: o.id == ^oid and o.tenant_id == ^tid and o.status in ["draft", "active"],
        lock: "FOR SHARE"
    ) || Repo.rollback(:invalid_setup)

    row = Repo.get_by(Binding, tenant_id: tid, occasion_id: oid)
    if row && row.book_id != bid, do: Repo.rollback(:binding_taken)

    cond do
      active && is_nil(row) ->
        Repo.insert!(%Binding{tenant_id: tid, book_id: bid, occasion_id: oid})

      !active && row ->
        Repo.delete!(row)

      true ->
        :ok
    end

    if active, do: "OccasionBookBound", else: "OccasionBookUnbound"
  end

  defp mutate!(tid, bid, "account_create", p, eid, version, actor, app) do
    account_fields!(p, false)
    attrs = account_attrs!(p, bid, eid, nil)
    reserve!(bid, attrs.number, nil)

    Repo.insert!(
      struct!(
        Account,
        Map.merge(attrs, %{
          id: eid,
          actor_identity_id: actor,
          application_id: app,
          tenant_id: tid,
          book_id: bid,
          version: version,
          reserved_numbers: if(attrs.number, do: [attrs.number], else: [])
        })
      )
    )

    "AccountCreated"
  end

  defp mutate!(tid, bid, "account_revise", p, _eid, version, actor, app) do
    account_fields!(p, true)
    id = uuid!(p["account_id"])

    account =
      Repo.get_by(Account, tenant_id: tid, book_id: bid, id: id) || Repo.rollback(:not_found)

    unless is_integer(p["expected_account_version"]) &&
             p["expected_account_version"] == account.version,
           do: Repo.rollback(:version_conflict)

    attrs = account_attrs!(p, bid, id, account) |> Map.put(:active, boolean!(p["active"]))
    reserve!(bid, attrs.number, id)

    attrs =
      Map.merge(attrs, %{
        version: version,
        actor_identity_id: actor,
        application_id: app,
        reserved_numbers:
          Enum.uniq(Enum.reject([attrs.number | account.reserved_numbers], &is_nil/1))
      })

    Repo.update!(Ecto.Changeset.change(account, attrs))

    cond do
      account.active && !attrs.active -> "AccountDeactivated"
      !account.active && attrs.active -> "AccountReactivated"
      true -> "AccountRevised"
    end
  end

  defp account_fields!(p, revise) do
    required =
      if revise,
        do: ~w(account_id name kind active expected_account_version expected_version),
        else: ~w(name kind expected_version)

    allowed = required ++ ~w(number vat_code category position formula)

    unless Enum.all?(required, &Map.has_key?(p, &1)) && Enum.all?(Map.keys(p), &(&1 in allowed)),
      do: Repo.rollback(:invalid_setup)
  end

  defp account_attrs!(p, bid, id, previous) do
    kind =
      case p["kind"] do
        "heading" -> "header"
        "total" -> "calculation"
        other -> other
      end

    name = p["name"]
    rows = Repo.all(from a in Account, where: a.book_id == ^bid)

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
           do: Repo.rollback(:invalid_setup)

    if Enum.any?(rows, &(&1.id != id && &1.position == position)),
      do: Repo.rollback(:position_taken)

    number = if kind == "posting", do: p["number"]
    vat = if kind == "posting", do: p["vat_code"]
    category = if kind == "posting", do: p["category"]

    unless kind != "posting" ||
             (is_binary(number) && Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/, number) &&
                (is_nil(vat) || vat in @vat_codes) &&
                (is_nil(category) || category in @categories)),
           do: Repo.rollback(:invalid_setup)

    formula = if kind == "calculation", do: p["formula"]
    candidate = %{id: id, number: number, kind: kind, formula_refs: %{}}
    chart = [candidate | Enum.reject(rows, &(&1.id == id))]

    refs =
      if kind == "calculation" do
        case Ep.Finance.Formula.references(formula, chart, previous) do
          {:ok, refs} -> refs
          _ -> Repo.rollback(:invalid_formula)
        end
      else
        %{}
      end

    unless Ep.Finance.Formula.acyclic?([
             %{candidate | formula_refs: refs} | Enum.reject(rows, &(&1.id == id))
           ]),
           do: Repo.rollback(:invalid_formula)

    %{
      number: number,
      name: String.trim(name),
      kind: kind,
      position: position,
      vat_code: vat,
      category: category,
      formula: formula,
      formula_refs: refs
    }
  end

  defp reserve!(_bid, nil, _self), do: :ok

  defp reserve!(bid, number, self) do
    if Repo.exists?(
         from a in Account,
           where:
             a.book_id == ^bid and ^number in a.reserved_numbers and
               a.id != ^(self || "00000000-0000-0000-0000-000000000000")
       ),
       do: Repo.rollback(:number_taken)
  end

  defp snapshot(bid) do
    accounts =
      Repo.all(
        from a in Account, where: a.book_id == ^bid, order_by: [asc: a.position, asc: a.id]
      )

    bindings = Repo.all(from b in Binding, where: b.book_id == ^bid, order_by: b.occasion_id)

    %{
      "accounts" =>
        Enum.map(
          accounts,
          &Map.take(&1, [
            :id,
            :number,
            :vat_code,
            :category,
            :position,
            :formula,
            :formula_refs,
            :name,
            :kind,
            :active,
            :version,
            :actor_identity_id,
            :application_id
          ])
        ),
      "bindings" => Enum.map(bindings, &%{occasion_id: &1.occasion_id})
    }
  end

  defp stewards(bid),
    do:
      Repo.all(
        from s in Steward,
          where: s.book_id == ^bid and s.active,
          order_by: s.identity_id,
          select: %{identity_id: s.identity_id, can_reopen_periods: s.can_reopen_periods}
      )

  defp candidates(tid) do
    ids =
      Repo.all(
        from a in Ep.Tenancy.Access,
          where: a.tenant_id == ^tid and a.status == "active",
          select: a.identity_id
      ) ++
        Repo.all(
          from a in Ep.Occasions.Admin,
            where: a.tenant_id == ^tid and a.status == "active",
            select: a.identity_id
        )

    Repo.all(
      from i in Ep.Auth.Identity,
        where: i.id in ^ids and i.status == "active" and not is_nil(i.verified_at),
        order_by: i.email,
        select: %{identity_id: i.id, label: i.email}
    )
  end

  defp occasions(tid),
    do:
      Repo.all(
        from o in Ep.Occasions.Occasion,
          where: o.tenant_id == ^tid and o.status in ["draft", "active"],
          order_by: o.name,
          select: %{occasion_id: o.id, name: o.name}
      )

  def running!(tid) do
    control =
      Repo.one(
        from c in Control,
          where: c.tenant_id == ^tid and c.name == "finance_setup",
          lock: "FOR SHARE"
      )

    if (control && control.state != "running") ||
         (is_nil(control) && Repo.exists?(from s in SetupState, where: s.tenant_id == ^tid)),
       do: Repo.rollback(:view_stopped)
  end

  defp ensure_control!(tid) do
    Events.lock!("finance-setup-control:" <> tid)

    unless Repo.get_by(Control, tenant_id: tid, name: "finance_setup"),
      do: Repo.insert!(%Control{tenant_id: tid, name: "finance_setup"})
  end

  defp fields!(p, allowed) do
    unless Enum.sort(Map.keys(p)) == Enum.sort(allowed), do: Repo.rollback(:invalid_setup)
  end

  defp boolean!(v) when is_boolean(v), do: v
  defp boolean!(_), do: Repo.rollback(:invalid_setup)

  defp uuid(v) do
    case Ecto.UUID.cast(v) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp uuid!(v) do
    case uuid(v) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_setup)
    end
  end
end
