defmodule Ep.Monitoring.Alerts do
  @moduledoc "Governed rule evaluation and durable API delivery handoff. Projection replay never runs this evaluator."
  import Ecto.Query
  alias Ep.{Monitoring, Repo, Events}
  alias Ep.Monitoring.{Rule, Alert, Source, Configuration}

  def rules(principal, tid, oid) do
    with {:ok, tid} <- Configuration.optional_uuid(tid),
         {:ok, oid} <- Configuration.optional_uuid(oid) do
      Repo.transaction(fn ->
        Configuration.authorize!(principal, tid, oid)

        query =
          from r in Rule,
            join: s in Source,
            on: s.id == r.source_id,
            where:
              fragment("? IS NOT DISTINCT FROM ?::uuid", s.tenant_id, type(^tid, :binary_id)),
            select: r,
            order_by: r.inserted_at

        query = if oid, do: from([r, s] in query, where: s.occasion_id == ^oid), else: query
        %{rules: Enum.map(Repo.all(query), &serialize/1)}
      end)
    else
      _ -> {:error, :invalid_query}
    end
  end

  def configure(principal, tid, params, key) do
    with {:ok, tid} <- Configuration.optional_uuid(tid),
         {:ok, sid} <- Monitoring.uuid(params["source_id"]),
         :ok <- Configuration.key(key),
         :ok <- validate_rule(params) do
      Repo.transaction(fn ->
        source = Repo.get(Source, sid) || Repo.rollback(:not_found)
        unless source.tenant_id == tid, do: Repo.rollback(:not_found)
        Configuration.authorize!(principal, tid, source.occasion_id)

        Configuration.command!(
          principal.identity_id,
          "MonitoringRuleConfigure",
          key,
          params,
          fn cid ->
            eligible =
              Configuration.eligible!(tid, source.occasion_id) |> Enum.map(& &1.identity_id)

            unless Enum.all?(params["recipient_ids"], &(&1 in eligible)),
              do: Repo.rollback(:invalid_configuration)

            attrs = %{
              source_id: sid,
              code: params["code"],
              threshold: params["threshold"],
              window_seconds: params["window_seconds"],
              cooldown_seconds: params["cooldown_seconds"],
              enabled: params["enabled"],
              recipient_ids: params["recipient_ids"],
              delivery_backend_id: params["delivery_backend_id"]
            }

            rule = Repo.insert!(struct!(Rule, Map.put(attrs, :version, 1)))

            Configuration.fact!(source, principal.identity_id, cid, "MonitoringRuleChanged", %{
              "rule_id" => rule.id,
              "configuration" => params
            })

            serialize(rule) |> Map.put(:command_id, cid)
          end
        )
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def suppress(principal, tid, id, params, key) do
    with {:ok, tid} <- Configuration.optional_uuid(tid),
         {:ok, id} <- Monitoring.uuid(id),
         :ok <- Configuration.key(key),
         true <- Enum.sort(Map.keys(params)) == ~w(expected_version reason until),
         true <- params["reason"] in ~w(maintenance investigation),
         {:ok, until, 0} <- parse_time(params["until"]),
         seconds = DateTime.diff(until, DateTime.utc_now()),
         true <- seconds in 0..86_400 do
      Repo.transaction(fn ->
        rule =
          Repo.one(from r in Rule, where: r.id == ^id, lock: "FOR UPDATE") ||
            Repo.rollback(:not_found)

        source = Repo.get!(Source, rule.source_id)
        unless source.tenant_id == tid, do: Repo.rollback(:not_found)
        Configuration.authorize!(principal, tid, source.occasion_id)

        Configuration.command!(
          principal.identity_id,
          "MonitoringSuppressionChange",
          key,
          {id, params},
          fn cid ->
            unless rule.version == params["expected_version"],
              do: Repo.rollback(:version_conflict)

            updated =
              Repo.update!(
                Ecto.Changeset.change(rule, suppressed_until: until, version: rule.version + 1)
              )

            Configuration.fact!(
              source,
              principal.identity_id,
              cid,
              "MonitoringSuppressionChanged",
              %{
                "rule_id" => id,
                "until" => DateTime.to_iso8601(until),
                "reason" => params["reason"]
              }
            )

            serialize(updated) |> Map.put(:command_id, cid)
          end
        )
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def set_enabled(principal, tid, id, params, key) do
    with {:ok, tid} <- Configuration.optional_uuid(tid),
         {:ok, id} <- Monitoring.uuid(id),
         :ok <- Configuration.key(key),
         true <- Enum.sort(Map.keys(params)) == ~w(enabled expected_version),
         true <- is_boolean(params["enabled"]) do
      Repo.transaction(fn ->
        rule =
          Repo.one(from r in Rule, where: r.id == ^id, lock: "FOR UPDATE") ||
            Repo.rollback(:not_found)

        source = Repo.get!(Source, rule.source_id)
        unless source.tenant_id == tid, do: Repo.rollback(:not_found)
        Configuration.authorize!(principal, tid, source.occasion_id)

        Configuration.command!(
          principal.identity_id,
          "MonitoringRuleState",
          key,
          {id, params},
          fn cid ->
            unless rule.version == params["expected_version"],
              do: Repo.rollback(:version_conflict)

            updated =
              Repo.update!(
                Ecto.Changeset.change(rule, enabled: params["enabled"], version: rule.version + 1)
              )

            Configuration.fact!(source, principal.identity_id, cid, "MonitoringRuleChanged", %{
              "rule_id" => id,
              "enabled" => params["enabled"]
            })

            serialize(updated)
          end
        )
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def statuses(principal, tid, oid) do
    with {:ok, tid} <- Configuration.optional_uuid(tid),
         {:ok, oid} <- Configuration.optional_uuid(oid) do
      Repo.transaction(fn ->
        Configuration.authorize!(principal, tid, oid)

        q =
          from a in Alert,
            join: r in Rule,
            on: r.id == a.rule_id,
            join: s in Source,
            on: s.id == r.source_id,
            where:
              fragment("? IS NOT DISTINCT FROM ?::uuid", s.tenant_id, type(^tid, :binary_id)),
            order_by: [desc: a.inserted_at],
            limit: 100,
            select: %{
              alert_id: a.id,
              issue_id: a.issue_id,
              state: a.state,
              code: r.code,
              updated_at: a.updated_at,
              attempt_id: a.attempt_id
            }

        q = if oid, do: from([a, r, s] in q, where: s.occasion_id == ^oid), else: q
        %{alerts: Repo.all(q)}
      end)
    else
      _ -> {:error, :invalid_query}
    end
  end

  def consider!(source, issue_id, event_id, observation) do
    now = DateTime.utc_now()

    rules =
      Repo.all(
        from r in Rule,
          where:
            r.source_id == ^source.id and r.code == ^observation["code"] and r.enabled == true
      )

    Enum.each(rules, fn rule ->
      Events.lock!("monitoring-alert-rule:" <> rule.id)
      rule = Repo.get!(Rule, rule.id)
      suppressed = rule.suppressed_until && DateTime.compare(rule.suppressed_until, now) == :gt
      cooldown = DateTime.add(now, -rule.cooldown_seconds, :second)

      recent_alert =
        Repo.exists?(from a in Alert, where: a.rule_id == ^rule.id and a.inserted_at > ^cooldown)

      cutoff = DateTime.add(now, -rule.window_seconds, :second)
      # Only committed/this-transaction accepted observations count; issue lifetime counts do not.
      count =
        Repo.one(
          from e in Ep.Events.Event,
            join: d in Ep.Events.Details,
            on: d.event_id == e.id,
            where:
              e.stream_type == "monitoring_issue" and e.inserted_at > ^cutoff and
                fragment("?->'observation'->>'source_id'", d.payload) == ^source.id and
                fragment("?->'observation'->>'code'", d.payload) == ^rule.code,
            select:
              fragment("COALESCE(SUM((?->'observation'->>'occurrence_count')::int),0)", d.payload)
        )

      if rule.enabled && !suppressed && !recent_alert && count >= rule.threshold do
        alert =
          Repo.insert!(%Alert{
            rule_id: rule.id,
            issue_id: issue_id,
            trigger_event_id: event_id,
            attempt_id: Ecto.UUID.generate(),
            state: "pending"
          })

        cid = Ecto.UUID.generate()

        Configuration.fact!(
          source,
          source.identity_id,
          cid,
          "MonitoringAlertRequested",
          %{"alert_id" => alert.id, "rule_id" => rule.id, "issue_id" => issue_id},
          "monitoring_alert",
          alert.id
        )
      end
    end)
  end

  def claim(backend, params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ~w(request_id))),
         {:ok, request_id} <- Monitoring.uuid(params["request_id"]) do
      Repo.transaction(fn ->
        Ep.Monitoring.Privacy.serving!()
        Events.lock!("monitoring-alert-claim:" <> backend <> ":" <> request_id)
        now = DateTime.utc_now()

        expired =
          Repo.all(
            from a in Alert,
              join: r in Rule,
              on: r.id == a.rule_id,
              where:
                a.state == "claimed" and a.claimed_until < ^now and
                  r.delivery_backend_id == ^backend,
              select: a,
              lock: "FOR UPDATE SKIP LOCKED",
              limit: 10
          )

        Enum.each(expired, fn a -> outcome!(a, backend, "unknown") end)

        old =
          Repo.all(
            from a in Alert,
              join: r in Rule,
              on: r.id == a.rule_id,
              where:
                a.claim_request_id == ^request_id and a.state == "claimed" and
                  a.claimed_until > ^now and r.delivery_backend_id == ^backend,
              select: a,
              limit: 1,
              lock: "FOR UPDATE"
          )

        pending =
          if old == [],
            do:
              Repo.all(
                from a in Alert,
                  join: r in Rule,
                  on: r.id == a.rule_id,
                  where:
                    a.state == "pending" and r.delivery_backend_id == ^backend and
                      r.enabled == true and
                      (is_nil(r.suppressed_until) or r.suppressed_until <= ^now),
                  order_by: a.inserted_at,
                  limit: 1,
                  select: a,
                  lock: "FOR UPDATE SKIP LOCKED"
              ),
            else: old

        material =
          Enum.flat_map(pending, fn alert ->
            rule = Repo.get!(Rule, alert.rule_id)
            source = Repo.get!(Source, rule.source_id)
            eligible = Configuration.eligible!(source.tenant_id, source.occasion_id)
            recipients = Enum.filter(eligible, &(&1.identity_id in rule.recipient_ids))

            if Configuration.active_source?(source) && rule.enabled && recipients != [] do
              alert =
                if alert.state == "pending" do
                  updated =
                    Repo.update!(
                      Ecto.Changeset.change(alert,
                        state: "claimed",
                        claim_request_id: request_id,
                        claimed_until: DateTime.add(now, 300, :second)
                      )
                    )

                  Configuration.fact!(
                    source,
                    source.identity_id,
                    Ecto.UUID.generate(),
                    "MonitoringAlertClaimed",
                    %{
                      "alert_id" => alert.id,
                      "backend_id" => backend,
                      "attempt_id" => alert.attempt_id
                    },
                    "monitoring_alert",
                    alert.id
                  )

                  updated
                else
                  alert
                end

              {:ok, entry} = Ep.Monitoring.Catalogue.fetch(rule.code)

              [
                %{
                  alert_id: alert.id,
                  attempt_id: alert.attempt_id,
                  tenant_id: source.tenant_id,
                  occasion_id: source.occasion_id,
                  issue_id: alert.issue_id,
                  code: rule.code,
                  safe_message: entry.safe_message,
                  recipients: Enum.map(recipients, & &1.label)
                }
              ]
            else
              outcome!(alert, backend, "cancelled")
              []
            end
          end)

        %{alerts: material}
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def outcome(backend, id, params) do
    with {:ok, id} <- Monitoring.uuid(id),
         true <- Enum.sort(Map.keys(params)) == ~w(attempt_id status),
         {:ok, attempt} <- Monitoring.uuid(params["attempt_id"]),
         true <- params["status"] in ~w(provider_accepted rejected unknown test_accepted) do
      Repo.transaction(fn ->
        alert =
          Repo.one(from a in Alert, where: a.id == ^id, lock: "FOR UPDATE") ||
            Repo.rollback(:not_found)

        rule = Repo.get!(Rule, alert.rule_id)

        unless rule.delivery_backend_id == backend && alert.attempt_id == attempt,
          do: Repo.rollback(:not_found)

        cond do
          alert.state == params["status"] ->
            %{status: alert.state, replayed: true}

          alert.state != "claimed" ->
            Repo.rollback(:version_conflict)

          true ->
            outcome!(alert, backend, params["status"])
            %{status: params["status"], replayed: false}
        end
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  defp outcome!(alert, backend, status) do
    rule = Repo.get!(Rule, alert.rule_id)
    source = Repo.get!(Source, rule.source_id)
    Repo.update!(Ecto.Changeset.change(alert, state: status))

    Configuration.fact!(
      source,
      source.identity_id,
      Ecto.UUID.generate(),
      "MonitoringAlertOutcomeRecorded",
      %{
        "alert_id" => alert.id,
        "attempt_id" => alert.attempt_id,
        "backend_id" => backend,
        "status" => status
      },
      "monitoring_alert",
      alert.id
    )
  end

  defp validate_rule(p) do
    with true <-
           Enum.sort(Map.keys(p)) ==
             ~w(code cooldown_seconds delivery_backend_id enabled recipient_ids source_id threshold window_seconds),
         {:ok, _} <- Ep.Monitoring.Catalogue.fetch(p["code"]),
         true <- is_integer(p["threshold"]) and p["threshold"] in 1..10_000,
         true <- is_integer(p["window_seconds"]) and p["window_seconds"] in 60..3600,
         true <- is_integer(p["cooldown_seconds"]) and p["cooldown_seconds"] in 60..86_400,
         true <- is_boolean(p["enabled"]),
         true <- is_list(p["recipient_ids"]) and length(p["recipient_ids"]) in 1..10,
         true <- Enum.all?(p["recipient_ids"], &match?({:ok, _}, Monitoring.uuid(&1))),
         true <-
           Map.has_key?(Application.get_env(:ep, :backend_tokens, %{}), p["delivery_backend_id"]) do
      :ok
    else
      _ -> :error
    end
  end

  defp parse_time(value) when is_binary(value), do: DateTime.from_iso8601(value)
  defp parse_time(_), do: :error

  def serialize(r),
    do: %{
      rule_id: r.id,
      source_id: r.source_id,
      code: r.code,
      threshold: r.threshold,
      window_seconds: r.window_seconds,
      cooldown_seconds: r.cooldown_seconds,
      enabled: r.enabled,
      suppressed_until: r.suppressed_until,
      recipient_ids: r.recipient_ids,
      delivery_backend_id: r.delivery_backend_id,
      version: r.version
    }
end
