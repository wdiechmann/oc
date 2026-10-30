defmodule Ep.Finance.Setup do
  @moduledoc "Book-local configuration authority and guarded setup commands. Never financial execution."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Finance.{Account, Binding, Book, SetupState, SetupView, SetupWorker, Steward}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Projections.Control

  @actions ~w(steward binding account_create account_revise)

  def get(principal, tid, bid) do
    with {:ok, tid} <- uuid(tid), {:ok, bid} <- uuid(bid) do
      Repo.transaction(fn ->
        {book, admin, steward} = access!(principal, tid, bid)
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

  def command(principal, tid, bid, action, params, key, application_id \\ "internal") do
    with {:ok, tid} <- uuid(tid),
         {:ok, bid} <- uuid(bid),
         true <- action in @actions,
         true <- is_map(params),
         true <- is_binary(key) and Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key) do
      Repo.transaction(fn ->
        {_book, admin, steward} = access!(principal, tid, bid)
        unless if(action == "steward", do: admin, else: steward), do: Repo.rollback(:not_found)
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

  defp access!(principal, tid, bid) do
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
        Repo.update!(Ecto.Changeset.change(row, active: active))
    end

    if active, do: "FinanceStewardAssigned", else: "FinanceStewardRevoked"
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
    fields!(p, ~w(number name kind expected_version))
    attrs = account_attrs!(p)
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
          reserved_numbers: [attrs.number]
        })
      )
    )

    "AccountCreated"
  end

  defp mutate!(tid, bid, "account_revise", p, _eid, version, actor, app) do
    fields!(p, ~w(account_id number name kind active expected_account_version expected_version))
    id = uuid!(p["account_id"])

    account =
      Repo.get_by(Account, tenant_id: tid, book_id: bid, id: id) || Repo.rollback(:not_found)

    unless is_integer(p["expected_account_version"]) &&
             p["expected_account_version"] == account.version,
           do: Repo.rollback(:version_conflict)

    attrs = account_attrs!(p) |> Map.put(:active, boolean!(p["active"]))
    reserve!(bid, attrs.number, id)

    attrs =
      Map.merge(attrs, %{
        version: version,
        actor_identity_id: actor,
        application_id: app,
        reserved_numbers: Enum.uniq([attrs.number | account.reserved_numbers])
      })

    Repo.update!(Ecto.Changeset.change(account, attrs))

    cond do
      account.active && !attrs.active -> "AccountDeactivated"
      !account.active && attrs.active -> "AccountReactivated"
      true -> "AccountRevised"
    end
  end

  defp account_attrs!(p) do
    number = p["number"]
    name = p["name"]

    unless is_binary(number) && Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/, number) &&
             is_binary(name) && String.length(String.trim(name)) in 1..120 &&
             p["kind"] in ~w(posting heading total),
           do: Repo.rollback(:invalid_setup)

    %{number: number, name: String.trim(name), kind: p["kind"]}
  end

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
    accounts = Repo.all(from a in Account, where: a.book_id == ^bid, order_by: [asc: a.number])
    bindings = Repo.all(from b in Binding, where: b.book_id == ^bid, order_by: b.occasion_id)

    %{
      "accounts" =>
        Enum.map(
          accounts,
          &Map.take(&1, [
            :id,
            :number,
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
          select: %{identity_id: s.identity_id}
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
