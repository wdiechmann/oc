defmodule Ep.Finance.Periods do
  @moduledoc "Governed book-local periods. Posting callers must retain lock_open! in their own authorized acceptance transaction."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Finance.{Period, PeriodState, PeriodView, PeriodWorker, Setup, Steward}
  alias Ep.Projections.Control
  @actions ~w(create revise open close reopen)

  def list(principal, tid, bid) do
    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid) do
      Repo.transaction(fn ->
        {book, admin, steward} = Setup.authorize!(principal, tid, bid)
        running!(tid)
        state = Repo.get(PeriodState, bid)
        latest = if state, do: state.version, else: 0
        row = Repo.get(PeriodView, bid)
        source = if row, do: row.source_version, else: 0

        %{
          tenant_id: tid,
          book_id: bid,
          book_name: book.name,
          timezone: book.timezone,
          fiscal_year_start_month: book.fiscal_year_start_month,
          accounting_authority: book.accounting_authority,
          status: if(source == latest, do: "ready", else: "pending"),
          source_version: source,
          latest_version: latest,
          permissions: %{
            configure: steward,
            reopen: steward && can_reopen?(principal, tid, bid),
            assign_stewards: admin
          },
          periods: if(row, do: row.data["periods"], else: [])
        }
      end)
    end
  end

  def command(principal, tid, bid, action, params, key, application_id \\ "internal") do
    with {:ok, tid} <- uuid(tid),
         {:ok, bid} <- uuid(bid),
         true <- action in @actions && is_map(params),
         true <- is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key) do
      Repo.transaction(fn ->
        {_book, _admin, steward} = Setup.authorize!(principal, tid, bid)

        unless steward && (action != "reopen" || can_reopen?(principal, tid, bid)),
          do: Repo.rollback(:not_found)

        Events.lock!("finance-periods:" <> bid)
        type = "FinancePeriod:" <> action
        Events.lock!("command:" <> principal.identity_id <> ":" <> type <> ":" <> key)
        fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, params}))

        case Repo.get_by(CommandReceipt,
               identity_id: principal.identity_id,
               command_type: type,
               idempotency_key: key
             ) do
          nil ->
            state =
              Repo.get(PeriodState, bid) ||
                Repo.insert!(%PeriodState{book_id: bid, tenant_id: tid})

            unless is_integer(params["expected_version"]) &&
                     params["expected_version"] == state.version,
                   do: Repo.rollback(:version_conflict)

            cid = Ecto.UUID.generate()
            eid = Ecto.UUID.generate()

            {period, event_type} =
              mutate!(
                tid,
                bid,
                action,
                params,
                eid,
                state.version + 1,
                principal.identity_id,
                application_id
              )

            ensure_control!(tid)

            snapshot =
              Map.take(period, [
                :id,
                :tenant_id,
                :book_id,
                :name,
                :start_date,
                :end_date,
                :status,
                :version,
                :actor_identity_id,
                :application_id,
                :reason
              ])

            [event] =
              Events.append!(
                %{
                  id: eid,
                  scope: "tenant",
                  scope_key: "tenant:" <> tid,
                  tenant_id: tid,
                  stream_type: "finance_periods",
                  stream_id: bid,
                  actor_identity_id: principal.identity_id,
                  command_id: cid,
                  correlation_id: cid
                },
                [{event_type, %{"period" => snapshot}}]
              )

            unless event.stream_version == state.version + 1, do: Repo.rollback(:version_conflict)
            Repo.update!(Ecto.Changeset.change(state, version: event.stream_version))
            Repo.insert!(%Outbox{tenant_id: tid, event_id: event.id})
            Oban.insert!(PeriodWorker.new(%{tenant_id: tid}))

            result = %{
              "command_id" => cid,
              "tenant_id" => tid,
              "book_id" => bid,
              "period_id" => period.id,
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
      _ -> {:error, :invalid_period}
    end
  end

  @doc "Internal date/state guard only, NOT financial authorization. Call after book activation/accounting-mode and money authority checks, holding this transaction through ledger/event acceptance."
  def lock_open!(tid, bid, posting_date) do
    unless Repo.in_transaction?(), do: raise("Period guards require an acceptance transaction")

    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid), {:ok, date} <- date(posting_date) do
      row =
        Repo.one(
          from p in Period,
            where:
              p.tenant_id == ^tid and p.book_id == ^bid and p.start_date <= ^date and
                p.end_date >= ^date,
            lock: "FOR SHARE"
        )

      unless row && row.status == "open", do: Repo.rollback(:period_not_open)
      row
    else
      _ -> Repo.rollback(:invalid_period)
    end
  end

  defp mutate!(tid, bid, "create", p, eid, version, actor, app) do
    fields!(p, ~w(name start_date end_date expected_version))
    attrs = dates!(p)
    overlap!(tid, bid, attrs, nil)

    row =
      Repo.insert!(
        struct!(
          Period,
          Map.merge(attrs, %{
            id: eid,
            tenant_id: tid,
            book_id: bid,
            version: version,
            actor_identity_id: actor,
            application_id: app
          })
        )
      )

    {row, "PeriodCreated"}
  end

  defp mutate!(tid, bid, action, p, _eid, version, actor, app) do
    fields =
      case action do
        "revise" ->
          ~w(period_id name start_date end_date expected_version expected_period_version)

        "reopen" ->
          ~w(period_id reason expected_version expected_period_version)

        _ ->
          ~w(period_id expected_version expected_period_version)
      end

    fields!(p, fields)
    id = uuid!(p["period_id"])

    row =
      Repo.one(
        from x in Period,
          where: x.tenant_id == ^tid and x.book_id == ^bid and x.id == ^id,
          lock: "FOR UPDATE"
      ) || Repo.rollback(:not_found)

    unless is_integer(p["expected_period_version"]) && p["expected_period_version"] == row.version,
      do: Repo.rollback(:version_conflict)

    {attrs, type} =
      case {action, row.status} do
        {"revise", "draft"} ->
          attrs = dates!(p)
          overlap!(tid, bid, attrs, id)
          {attrs, "PeriodRevised"}

        {"open", "draft"} ->
          {%{status: "open", reason: nil}, "PeriodOpened"}

        {"close", "open"} ->
          {%{status: "closed", reason: nil}, "PeriodClosed"}

        {"reopen", "closed"} ->
          {%{status: "open", reason: reason!(p["reason"])}, "PeriodReopened"}

        _ ->
          Repo.rollback(:invalid_transition)
      end

    attrs = Map.merge(attrs, %{version: version, actor_identity_id: actor, application_id: app})
    {Repo.update!(Ecto.Changeset.change(row, attrs)), type}
  end

  defp dates!(p) do
    with name when is_binary(name) <- p["name"],
         true <- String.length(String.trim(name)) in 1..120,
         {:ok, start} <- date(p["start_date"]),
         {:ok, finish} <- date(p["end_date"]),
         true <- Date.compare(start, finish) != :gt do
      %{name: String.trim(name), start_date: start, end_date: finish}
    else
      _ -> Repo.rollback(:invalid_period)
    end
  end

  defp overlap!(tid, bid, attrs, id) do
    query =
      from p in Period,
        where:
          p.tenant_id == ^tid and p.book_id == ^bid and p.start_date <= ^attrs.end_date and
            p.end_date >= ^attrs.start_date

    query = if id, do: from(p in query, where: p.id != ^id), else: query
    if Repo.exists?(query), do: Repo.rollback(:period_overlap)
  end

  defp reason!(value) when is_binary(value) do
    reason = String.trim(value)
    if String.length(reason) in 1..500, do: reason, else: Repo.rollback(:invalid_reason)
  end

  defp reason!(_), do: Repo.rollback(:invalid_reason)

  defp can_reopen?(principal, tid, bid),
    do:
      Repo.exists?(
        from s in Steward,
          where:
            s.tenant_id == ^tid and s.book_id == ^bid and s.identity_id == ^principal.identity_id and
              s.active and s.can_reopen_periods
      )

  def running!(tid) do
    control =
      Repo.one(
        from c in Control,
          where: c.tenant_id == ^tid and c.name == "finance_periods",
          lock: "FOR SHARE"
      )

    if (control && control.state != "running") ||
         (is_nil(control) && Repo.exists?(from s in PeriodState, where: s.tenant_id == ^tid)),
       do: Repo.rollback(:view_stopped)
  end

  defp ensure_control!(tid) do
    Events.lock!("finance-period-control:" <> tid)

    unless Repo.get_by(Control, tenant_id: tid, name: "finance_periods"),
      do: Repo.insert!(%Control{tenant_id: tid, name: "finance_periods"})
  end

  defp fields!(p, keys) do
    unless Enum.sort(Map.keys(p)) == Enum.sort(keys), do: Repo.rollback(:invalid_period)
  end

  defp date(%Date{year: year} = value) when year >= 1, do: {:ok, value}

  defp date(value) when is_binary(value) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value),
      do: valid_date(value),
      else: {:error, :invalid_period}
  end

  defp date(_), do: {:error, :invalid_period}

  defp valid_date(value) do
    case Date.from_iso8601(value) do
      {:ok, %Date{year: year} = date} when year >= 1 -> {:ok, date}
      _ -> {:error, :invalid_period}
    end
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp uuid!(value) do
    case uuid(value) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_period)
    end
  end
end
