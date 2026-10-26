defmodule Ep.Monitoring.Configuration do
  @moduledoc "Current-grant administration of reporting bindings; source secrets never leave backend authentication."
  import Ecto.Query
  alias Ep.{Events, Repo, Monitoring}
  alias Ep.Monitoring.{Source, Access}

  def sources(principal, tid, oid) do
    with {:ok, tid} <- optional_uuid(tid), {:ok, oid} <- optional_uuid(oid) do
      Repo.transaction(fn ->
        authorize!(principal, tid, oid)

        query =
          from s in Source,
            where:
              fragment("? IS NOT DISTINCT FROM ?::uuid", s.tenant_id, type(^tid, :binary_id)),
            order_by: [s.backend_id, s.inserted_at]

        query = if oid, do: from(s in query, where: s.occasion_id == ^oid), else: query

        %{
          sources: Repo.all(query) |> Enum.map(&serialize/1),
          backends: Map.keys(Application.get_env(:ep, :backend_tokens, %{}))
        }
      end)
    else
      _ -> {:error, :invalid_query}
    end
  end

  def register(principal, tid, params, key) do
    with {:ok, tid} <- optional_uuid(tid),
         {:ok, oid} <- optional_uuid(params["occasion_id"]),
         true <- Enum.all?(Map.keys(params), &(&1 in ~w(backend_id occasion_id))),
         backend when is_binary(backend) <- params["backend_id"],
         true <- Map.has_key?(Application.get_env(:ep, :backend_tokens, %{}), backend),
         :ok <- key(key) do
      Repo.transaction(fn ->
        authorize!(principal, tid, oid)

        command!(principal.identity_id, "MonitoringSourceRegister", key, {tid, params}, fn cid ->
          Events.lock!("monitoring-source-binding:" <> backend <> ":" <> Access.scope(tid, oid))

          existing =
            Repo.one(
              from s in Source,
                where:
                  s.backend_id == ^backend and
                    fragment(
                      "? IS NOT DISTINCT FROM ?::uuid",
                      s.tenant_id,
                      type(^tid, :binary_id)
                    ) and
                    s.status == "active" and
                    fragment(
                      "? IS NOT DISTINCT FROM ?::uuid",
                      s.occasion_id,
                      type(^oid, :binary_id)
                    ),
                limit: 1
            )

          source = existing || new_source!(backend, tid, oid)

          fact!(source, principal.identity_id, cid, "MonitoringSourceRegistered", %{
            "backend_id" => backend,
            "source_id" => source.id
          })

          serialize(source) |> Map.put(:command_id, cid)
        end)
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def revoke(principal, tid, id, key) do
    with {:ok, tid} <- optional_uuid(tid), {:ok, id} <- Monitoring.uuid(id), :ok <- key(key) do
      Repo.transaction(fn ->
        source =
          Repo.one(
            from s in Source,
              where:
                s.id == ^id and
                  fragment("? IS NOT DISTINCT FROM ?::uuid", s.tenant_id, type(^tid, :binary_id)),
              lock: "FOR UPDATE"
          ) || Repo.rollback(:not_found)

        authorize!(principal, tid, source.occasion_id)

        command!(principal.identity_id, "MonitoringSourceRevoke", key, {tid, id}, fn cid ->
          Repo.update!(Ecto.Changeset.change(source, status: "revoked"))

          fact!(source, principal.identity_id, cid, "MonitoringSourceRevoked", %{
            "source_id" => source.id
          })

          %{source_id: source.id, status: "revoked", command_id: cid}
        end)
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def bindings(backend) do
    rows =
      Repo.all(
        from s in Source,
          join: i in Ep.Auth.Identity,
          on: i.id == s.identity_id,
          where: s.backend_id == ^backend and s.status == "active" and i.status == "active",
          limit: 10_001
      )

    if length(rows) > 10_000 do
      {:error, :binding_limit}
    else
      {:ok,
       %{sources: Map.new(rows, fn s -> {Access.scope(s.tenant_id, s.occasion_id), s.id} end)}}
    end
  end

  def assignees(principal, tid, oid) do
    with {:ok, tid} <- optional_uuid(tid), {:ok, oid} <- optional_uuid(oid) do
      Repo.transaction(fn ->
        authorize!(principal, tid, oid)
        %{assignees: eligible!(tid, oid)}
      end)
    else
      _ -> {:error, :invalid_query}
    end
  end

  def eligible!(tid, oid),
    do:
      eligible_rows!(tid, oid)
      |> Enum.reject(&Ep.Monitoring.Privacy.subject_erased?(&1.identity_id))

  defp eligible_rows!(nil, _) do
    Repo.all(
      from p in Ep.Monitoring.Permission,
        join: i in Ep.Auth.Identity,
        on: i.id == p.identity_id,
        where:
          p.scope_key == "global" and p.permission == "platform_monitor" and p.status == "active" and
            i.status == "active" and not is_nil(i.email) and not is_nil(i.verified_at),
        select: %{identity_id: i.id, label: i.email},
        distinct: true,
        limit: 500
    )
  end

  defp eligible_rows!(tid, oid) do
    tenant =
      from a in Ep.Tenancy.Access,
        where: a.tenant_id == ^tid and a.status == "active" and a.role == "tenant_admin",
        select: a.identity_id

    ids = Repo.all(tenant)

    ids =
      if oid,
        do:
          ids ++
            Repo.all(
              from a in Ep.Occasions.Admin,
                where: a.tenant_id == ^tid and a.occasion_id == ^oid and a.status == "active",
                select: a.identity_id
            ),
        else: ids

    Repo.all(
      from i in Ep.Auth.Identity,
        where:
          i.id in ^ids and i.status == "active" and not is_nil(i.email) and
            not is_nil(i.verified_at),
        order_by: i.email,
        select: %{identity_id: i.id, label: i.email},
        limit: 500
    )
  end

  def active_source?(source) do
    parent =
      if source.tenant_id,
        do:
          Repo.one(
            from t in Ep.Tenancy.Tenant,
              where: t.id == ^source.tenant_id and t.status == "active",
              lock: "FOR SHARE"
          ),
        else: true

    occasion =
      if source.occasion_id,
        do:
          Repo.one(
            from o in Ep.Occasions.Occasion,
              where:
                o.id == ^source.occasion_id and o.tenant_id == ^source.tenant_id and
                  o.status in ["draft", "active"],
              lock: "FOR SHARE"
          ),
        else: true

    actor =
      Repo.one(
        from i in Ep.Auth.Identity,
          where: i.id == ^source.identity_id and i.status == "active",
          lock: "FOR SHARE"
      )

    current =
      Repo.one(
        from s in Source, where: s.id == ^source.id and s.status == "active", lock: "FOR SHARE"
      )

    !!(parent && occasion && actor && current)
  end

  def new_source!(backend, tid, oid) do
    party = Repo.insert!(%Ep.Auth.Party{kind: "machine"})
    actor = Repo.insert!(%Ep.Auth.Identity{party_id: party.id})

    Repo.insert!(%Source{
      backend_id: backend,
      identity_id: actor.id,
      tenant_id: tid,
      occasion_id: oid,
      status: "active"
    })
  end

  def fact!(
        source,
        actor,
        cid,
        type,
        payload,
        stream_type \\ "monitoring_configuration",
        stream_id \\ nil
      ) do
    Events.append!(
      %{
        scope:
          if(source.occasion_id,
            do: "occasion",
            else: if(source.tenant_id, do: "tenant", else: "global")
          ),
        scope_key: Access.scope(source.tenant_id, source.occasion_id),
        tenant_id: source.tenant_id,
        occasion_id: source.occasion_id,
        stream_type: stream_type,
        stream_id: stream_id || source.id,
        actor_identity_id: actor,
        command_id: cid,
        correlation_id: Process.get(:ep_correlation_id) || cid
      },
      [{type, payload}]
    )
  end

  def command!(actor, type, key, attrs, fun) do
    Events.lock!("monitoring-config-command:" <> actor <> ":" <> type <> ":" <> key)
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(attrs))

    case Repo.get_by(Ep.Events.CommandReceipt,
           identity_id: actor,
           command_type: type,
           idempotency_key: key
         ) do
      nil ->
        cid = Ecto.UUID.generate()
        result = fun.(cid) |> Jason.encode!() |> Jason.decode!()

        Repo.insert!(%Ep.Events.CommandReceipt{
          id: cid,
          identity_id: actor,
          command_type: type,
          idempotency_key: key,
          fingerprint: digest,
          result: result
        })

        Map.put(result, "replayed", false)

      %{fingerprint: ^digest, result: result} ->
        Map.put(result, "replayed", true)

      _ ->
        Repo.rollback(:idempotency_conflict)
    end
  end

  def authorize!(principal, tid, oid) do
    if tid, do: Monitoring.authorize!(principal, tid, oid), else: Access.platform!(principal)
    if Ep.Monitoring.Privacy.subject_erased?(principal.identity_id), do: Repo.rollback(:not_found)
  end

  def key(value) when is_binary(value),
    do: if(Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, value), do: :ok, else: :error)

  def key(_), do: :error
  def optional_uuid(nil), do: {:ok, nil}
  def optional_uuid(value), do: Monitoring.uuid(value)

  def serialize(s),
    do: %{
      source_id: s.id,
      backend_id: s.backend_id,
      tenant_id: s.tenant_id,
      occasion_id: s.occasion_id,
      status: s.status
    }
end
