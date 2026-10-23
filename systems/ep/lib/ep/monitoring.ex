defmodule Ep.Monitoring do
  @moduledoc "Governed monitoring ingestion and issue lifecycle. All caller scope comes from registered sources."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Events.CommandReceipt
  alias Ep.Monitoring.{Catalogue, Issue, Pending, Source}

  require Logger

  @input ~w(source_id source_observation_id code correlation_id observed_at related duration_ms occurrence_count)
  @related ~w(business_command_id event_id delivery_attempt_id job_id)

  def record(backend_id, params, delivery_only \\ false) do
    with {:ok, input} <- validate(params),
         {:ok, entry} <- catalogue(input["code"], delivery_only),
         :ok <- delivery_evidence(input, entry) do
      Repo.transaction(
        fn ->
          source = source!(backend_id, input["source_id"])

          if source.tenant_id do
            Repo.insert!(%Ep.Projections.Control{tenant_id: source.tenant_id, name: "monitoring"},
              on_conflict: :nothing
            )
          end

          command(
            source.identity_id,
            "Monitoring:" <> source.id,
            input["source_observation_id"],
            input,
            fn command_id ->
              Events.lock!("monitoring-rate:" <> source.id)
              recent = DateTime.add(DateTime.utc_now(), -60, :second)

              rate =
                Repo.aggregate(
                  from(r in CommandReceipt,
                    where:
                      r.identity_id == ^source.identity_id and
                        r.command_type == ^("Monitoring:" <> source.id) and
                        r.inserted_at > ^recent
                  ),
                  :count
                )

              if rate >= 600, do: Repo.rollback(:rate_limited)
              Events.lock!("monitoring-issue:" <> source.id <> ":" <> input["code"])
              issue = Repo.get_by(Issue, source_id: source.id, code: input["code"])
              now = DateTime.to_iso8601(DateTime.utc_now())

              data =
                Map.merge(Map.new(entry, fn {k, v} -> {Atom.to_string(k), v} end), %{
                  "code" => input["code"],
                  "application" => source.backend_id,
                  "source_id" => source.id,
                  "observed_at" => input["observed_at"],
                  "received_at" => now,
                  "correlation_id" => input["correlation_id"],
                  "related" => input["related"],
                  "duration_ms" => input["duration_ms"],
                  "source_observation_id" => input["source_observation_id"],
                  "occurrence_count" => input["occurrence_count"]
                })

              state =
                if issue && issue.data["state"] != "resolved",
                  do: issue.data["state"],
                  else: "open"

              snapshot =
                Map.merge(data, %{
                  "state" => state,
                  "owner_identity_id" => issue && issue.data["owner_identity_id"],
                  "first_seen" => if(issue, do: issue.data["first_seen"], else: now),
                  "last_seen" => now,
                  "count" =>
                    if(issue, do: issue.data["count"], else: 0) + input["occurrence_count"]
                })

              issue =
                issue ||
                  Repo.insert!(%Issue{
                    source_id: source.id,
                    code: input["code"],
                    version: 0,
                    data: snapshot
                  })

              types = [
                {if(entry.category == "delivery",
                   do: "DeliveryOutcomeRecorded",
                   else: "MonitoringObservationRecorded"
                 ), %{"observation" => data, "snapshot" => snapshot}}
              ]

              types =
                if issue.version == 0,
                  do: types ++ [{"MonitoringIssueOpened", %{"snapshot" => snapshot}}],
                  else: types

              types =
                if issue.data["state"] == "resolved",
                  do: types ++ [{"MonitoringIssueReopened", %{"snapshot" => snapshot}}],
                  else: types

              append!(
                source,
                issue,
                source.identity_id,
                command_id,
                input["correlation_id"],
                types,
                snapshot
              )
            end
          )
        end,
        timeout: 1_000,
        pool_timeout: 500
      )
    end
  end

  @doc "Safe EP-internal failure capture. No recursive ingestion and no raw exception text."
  def capture_exception(correlation_id, reporting_failure \\ false) do
    Logger.error("ep_request_failed",
      correlation_id: correlation_id,
      monitoring_code: "application.exception"
    )

    source_id = Application.get_env(:ep, :monitoring_source_id)

    if source_id && !reporting_failure && !Repo.in_transaction?() do
      try do
        result =
          record("ep", %{
            "source_id" => source_id,
            "source_observation_id" => Ecto.UUID.generate(),
            "correlation_id" => correlation_id,
            "code" => "application.exception",
            "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
          })

        unless match?({:ok, _}, result),
          do: Logger.warning("monitoring_capture_unavailable", correlation_id: correlation_id)
      rescue
        _ -> Logger.warning("monitoring_capture_unavailable", correlation_id: correlation_id)
      catch
        :exit, _ ->
          Logger.warning("monitoring_capture_unavailable", correlation_id: correlation_id)
      end
    end

    :ok
  end

  def action(principal, tid, id, params, key) do
    with {:ok, tid} <- uuid(tid),
         {:ok, id} <- uuid(id),
         :ok <- valid_action(params),
         :ok <- key(key) do
      Repo.transaction(fn ->
        Auth.lock_principal!(principal)
        issue = Repo.get(Issue, id) || Repo.rollback(:not_found)
        source = Repo.get!(Source, issue.source_id)
        authorize!(principal, tid, source.occasion_id)
        unless source.tenant_id == tid, do: Repo.rollback(:not_found)

        command(principal.identity_id, "MonitoringAction:" <> id, key, params, fn command_id ->
          Events.lock!("monitoring-issue:" <> source.id <> ":" <> issue.code)
          issue = Repo.get!(Issue, id)
          unless issue.version == params["expected_version"], do: Repo.rollback(:version_conflict)
          {type, changes} = action_changes!(principal, tid, source, params)
          snapshot = Map.merge(issue.data, changes)

          append!(
            source,
            issue,
            principal.identity_id,
            command_id,
            Process.get(:ep_correlation_id) || Ecto.UUID.generate(),
            [{type, %{"snapshot" => snapshot, "action" => params}}],
            snapshot
          )
        end)
      end)
    else
      _ -> {:error, :invalid_action}
    end
  end

  # Rechecks revocation, scope and tenant/occasion lifecycle under transaction locks on every query.
  def authorize!(principal, tid, oid) do
    Auth.lock_principal!(principal)

    tenant =
      Repo.one(
        from t in Ep.Tenancy.Tenant,
          where: t.id == ^tid and t.status == "active",
          lock: "FOR SHARE"
      )

    unless tenant, do: Repo.rollback(:not_found)

    tenant_access =
      Repo.one(
        from a in Ep.Tenancy.Access,
          where:
            a.tenant_id == ^tid and a.identity_id == ^principal.identity_id and
              a.role == "tenant_admin" and a.status == "active",
          lock: "FOR SHARE"
      )

    if oid do
      occasion =
        Repo.one(
          from o in Ep.Occasions.Occasion,
            where: o.tenant_id == ^tid and o.id == ^oid and o.status in ["draft", "active"],
            lock: "FOR SHARE"
        )

      unless occasion, do: Repo.rollback(:not_found)
    end

    unless tenant_access do
      unless oid, do: Repo.rollback(:not_found)

      grant =
        Repo.one(
          from a in Ep.Occasions.Admin,
            where:
              a.tenant_id == ^tid and a.occasion_id == ^oid and
                a.identity_id == ^principal.identity_id and a.status == "active",
            lock: "FOR SHARE"
        )

      unless grant, do: Repo.rollback(:not_found)
    end

    :ok
  end

  def source!(backend_id, id) do
    source =
      Repo.one(
        from s in Source,
          where: s.id == ^id and s.backend_id == ^backend_id and s.status == "active",
          lock: "FOR SHARE"
      ) || Repo.rollback(:not_found)

    identity =
      Repo.one(
        from i in Ep.Auth.Identity,
          where: i.id == ^source.identity_id and i.status == "active",
          lock: "FOR SHARE"
      )

    unless identity, do: Repo.rollback(:not_found)

    if source.tenant_id do
      tenant =
        Repo.one(
          from t in Ep.Tenancy.Tenant,
            where: t.id == ^source.tenant_id and t.status == "active",
            lock: "FOR SHARE"
        )

      unless tenant, do: Repo.rollback(:not_found)
    end

    if source.occasion_id do
      occasion =
        Repo.one(
          from o in Ep.Occasions.Occasion,
            where:
              o.id == ^source.occasion_id and o.tenant_id == ^source.tenant_id and
                o.status in ["draft", "active"],
            lock: "FOR SHARE"
        )

      unless occasion, do: Repo.rollback(:not_found)
    end

    source
  end

  defp append!(source, issue, actor, command_id, correlation_id, facts, snapshot) do
    scope =
      cond do
        source.occasion_id -> "occasion"
        source.tenant_id -> "tenant"
        true -> "global"
      end

    scope_key =
      case scope do
        "occasion" -> "tenant:#{source.tenant_id}:occasion:#{source.occasion_id}"
        "tenant" -> "tenant:#{source.tenant_id}"
        _ -> "global"
      end

    events =
      Events.append!(
        %{
          scope: scope,
          scope_key: scope_key,
          tenant_id: source.tenant_id,
          occasion_id: source.occasion_id,
          stream_type: "monitoring_issue",
          stream_id: issue.id,
          actor_identity_id: actor,
          command_id: command_id,
          correlation_id: correlation_id
        },
        facts
      )

    last = List.last(events)
    Repo.update!(Ecto.Changeset.change(issue, version: last.stream_version, data: snapshot))

    Enum.each(events, fn event ->
      Repo.insert!(%Pending{event_id: event.id, issue_id: issue.id})
    end)

    Oban.insert!(Ep.Monitoring.Worker.new(%{issue_id: issue.id}))

    %{
      "issue_id" => issue.id,
      "command_id" => command_id,
      "event_ids" => Enum.map(events, & &1.id),
      "stream_version" => last.stream_version,
      "correlation_id" => correlation_id
    }
  end

  defp command(actor, type, key, input, fun) do
    Events.lock!("monitoring-command:" <> actor <> ":" <> type <> ":" <> key)
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(input))

    case Repo.get_by(CommandReceipt, identity_id: actor, command_type: type, idempotency_key: key) do
      nil ->
        id = Ecto.UUID.generate()
        result = fun.(id)

        Repo.insert!(%CommandReceipt{
          id: id,
          identity_id: actor,
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
  end

  defp validate(p) when is_map(p) do
    with true <- Enum.all?(Map.keys(p), &(&1 in @input)),
         {:ok, sid} <- uuid(p["source_id"]),
         {:ok, oid} <- uuid(p["source_observation_id"]),
         {:ok, cid} <- uuid(p["correlation_id"]),
         {:ok, observed, 0} <- parse_time(p["observed_at"]),
         true <- abs(DateTime.diff(observed, DateTime.utc_now())) <= 86_400 * 30,
         count = Map.get(p, "occurrence_count", 1),
         true <- is_integer(count) and count in 1..10000,
         duration = p["duration_ms"],
         true <- is_nil(duration) or (is_integer(duration) and duration in 0..86_400_000),
         related = Map.get(p, "related", %{}),
         true <-
           is_map(related) and
             Enum.all?(related, fn {k, v} -> k in @related and match?({:ok, _}, uuid(v)) end) do
      {:ok,
       Map.merge(p, %{
         "source_id" => sid,
         "source_observation_id" => oid,
         "correlation_id" => cid,
         "observed_at" => DateTime.to_iso8601(observed),
         "occurrence_count" => count,
         "related" =>
           Map.new(related, fn {k, v} ->
             {:ok, canonical} = uuid(v)
             {k, canonical}
           end)
       })}
    else
      _ -> {:error, :invalid_observation}
    end
  end

  defp validate(_), do: {:error, :invalid_observation}
  defp parse_time(t) when is_binary(t), do: DateTime.from_iso8601(t)
  defp parse_time(_), do: :error

  defp delivery_evidence(input, %{category: "delivery"}) do
    if input["related"]["delivery_attempt_id"], do: :ok, else: {:error, :invalid_observation}
  end

  defp delivery_evidence(_, _), do: :ok

  defp catalogue(code, delivery_only) do
    case Catalogue.fetch(code) do
      {:ok, %{category: category} = entry} when not delivery_only or category == "delivery" ->
        {:ok, entry}

      _ ->
        {:error, :invalid_observation}
    end
  end

  defp valid_action(p) when is_map(p) do
    allowed =
      case p["action"] do
        a when a in ~w(acknowledge reopen) -> ~w(action expected_version)
        "resolve" -> ~w(action expected_version reason)
        "assign" -> ~w(action expected_version owner_identity_id)
        _ -> []
      end

    specific =
      case p["action"] do
        "resolve" -> p["reason"] in ~w(corrected duplicate accepted_risk)
        "assign" -> match?({:ok, _}, uuid(p["owner_identity_id"]))
        _ -> true
      end

    if allowed != [] and Enum.sort(Map.keys(p)) == Enum.sort(allowed) and specific and
         is_integer(p["expected_version"]) and p["expected_version"] > 0, do: :ok, else: :error
  end

  defp valid_action(_), do: :error

  defp action_changes!(_principal, tid, source, %{
         "action" => "assign",
         "owner_identity_id" => owner
       }) do
    {:ok, owner} =
      case uuid(owner) do
        {:ok, _} = result -> result
        _ -> Repo.rollback(:invalid_action)
      end

    owner_identity =
      Repo.one(
        from i in Ep.Auth.Identity,
          where: i.id == ^owner and i.status == "active",
          lock: "FOR SHARE"
      )

    unless owner_identity, do: Repo.rollback(:invalid_action)

    tenant_owner =
      Repo.one(
        from a in Ep.Tenancy.Access,
          where:
            a.tenant_id == ^tid and a.identity_id == ^owner and a.status == "active" and
              a.role == "tenant_admin",
          lock: "FOR SHARE"
      )

    occasion_owner =
      source.occasion_id &&
        Repo.one(
          from a in Ep.Occasions.Admin,
            where:
              a.tenant_id == ^tid and a.occasion_id == ^source.occasion_id and
                a.identity_id == ^owner and a.status == "active",
            lock: "FOR SHARE"
        )

    unless tenant_owner || occasion_owner, do: Repo.rollback(:invalid_action)
    {"MonitoringIssueAssigned", %{"owner_identity_id" => owner}}
  end

  defp action_changes!(_, _, _, %{"action" => "acknowledge"}),
    do: {"MonitoringIssueAcknowledged", %{"state" => "acknowledged"}}

  defp action_changes!(_, _, _, %{"action" => "resolve", "reason" => reason})
       when reason in ~w(corrected duplicate accepted_risk),
       do: {"MonitoringIssueResolved", %{"state" => "resolved", "resolution_reason" => reason}}

  defp action_changes!(_, _, _, %{"action" => "reopen"}),
    do: {"MonitoringIssueReopened", %{"state" => "open"}}

  defp action_changes!(_, _, _, _), do: Repo.rollback(:invalid_action)
  def uuid(value) when is_binary(value), do: Ecto.UUID.cast(value)
  def uuid(_), do: :error

  defp key(value) when is_binary(value),
    do: if(Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, value), do: :ok, else: :error)

  defp key(_), do: :error
end
