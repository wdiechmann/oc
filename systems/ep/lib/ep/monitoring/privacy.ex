defmodule Ep.Monitoring.Privacy do
  @moduledoc "Live monitoring redaction and retention. Erasure ledger also gates restored/replayed serving. Backup closure is separate."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Monitoring.{Subject, Erasure, Issue, Source, View, Diagnostic, Redaction}

  def subject_hash(id) do
    key =
      Application.get_env(:ep, :monitoring_privacy_key) ||
        Application.fetch_env!(:ep, EpWeb.Endpoint)[:secret_key_base]

    unless is_binary(key) && byte_size(key) >= 32,
      do: raise("Monitoring privacy key must remain stable across restore")

    :crypto.mac(:hmac, :sha256, key, id) |> Base.encode16(case: :lower)
  end

  def index!(event, payload) do
    direct = references(payload) ++ [event.actor_identity_id]
    command_ids = related(payload, "business_command_id")
    event_ids = related(payload, "event_id")

    command_actors =
      if command_ids == [],
        do: [],
        else:
          Repo.all(
            from c in Ep.Events.CommandReceipt, where: c.id in ^command_ids, select: c.identity_id
          )

    event_actors =
      if event_ids == [],
        do: [],
        else:
          Repo.all(
            from e in Ep.Events.Event, where: e.id in ^event_ids, select: e.actor_identity_id
          )

    now = DateTime.utc_now()

    rows =
      (direct ++ command_actors ++ event_actors)
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.map(fn id ->
        %{event_id: event.id, subject_hash: subject_hash(id), inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(Subject, rows, on_conflict: :nothing)
  end

  def subject_erased?(identity_id), do: !!Repo.get(Erasure, subject_hash(identity_id))

  def on_append!(event) do
    if erased?(event.id), do: redact!(event.id, "erasure", privacy_actor!())
  end

  def placeholder,
    do: %{
      "privacy_erased" => true,
      "safe_message" => "Monitoring content removed under privacy/retention policy.",
      "state" => "redacted",
      "count" => 0
    }

  def suppress(query) do
    from v in query,
      where:
        not exists(
          subquery(
            from s in Subject,
              join: r in Erasure,
              on: r.subject_hash == s.subject_hash,
              join: e in Ep.Events.Event,
              on: e.id == s.event_id,
              where:
                s.event_id == parent_as(:monitoring_view).id or
                  (parent_as(:monitoring_view).kind == "issue" and
                     e.stream_id == parent_as(:monitoring_view).issue_id and
                     e.stream_version == parent_as(:monitoring_view).source_version)
          )
        )
  end

  def serving! do
    if Repo.exists?(from e in Erasure, where: e.state == "pending"),
      do: Repo.rollback(:privacy_cleanup_pending)
  end

  def erased?(event_id) do
    Repo.exists?(
      from s in Subject,
        join: e in Erasure,
        on: e.subject_hash == s.subject_hash,
        where: s.event_id == ^event_id
    )
  end

  def erase(identity_id) do
    {:ok, id} = Ecto.UUID.cast(identity_id)
    erase_hash(subject_hash(id), id)
  end

  def erase_hash(hash, id \\ nil) do
    unless is_binary(hash) && Regex.match?(~r/^[0-9a-f]{64}$/, hash),
      do: raise("Invalid privacy subject digest")

    id =
      id ||
        Repo.all(from i in Ep.Auth.Identity, select: i.id)
        |> Enum.find(&(subject_hash(&1) == hash))

    {:ok, _} =
      Repo.transaction(fn ->
        Events.lock!("monitoring-erasure:" <> hash)

        Repo.insert!(%Erasure{subject_hash: hash, state: "pending"},
          on_conflict: [set: [state: "pending"]],
          conflict_target: :subject_hash
        )
      end)

    backfill()
    actor = privacy_actor!()
    event_ids = Repo.all(from s in Subject, where: s.subject_hash == ^hash, select: s.event_id)

    Enum.chunk_every(event_ids, 100)
    |> Enum.each(fn ids ->
      {:ok, _} = Repo.transaction(fn -> Enum.each(ids, &redact!(&1, "erasure", actor)) end)
    end)

    affected =
      Repo.all(
        from e in Ep.Events.Event,
          where: e.id in ^event_ids and e.stream_type == "monitoring_issue",
          select: e.stream_id,
          distinct: true
      )

    Enum.each(affected, fn issue_id ->
      {:ok, _} =
        Repo.transaction(fn ->
          issue = Repo.get!(Issue, issue_id)
          source = Repo.get!(Source, issue.source_id)
          Events.lock!("monitoring-issue:" <> source.id <> ":" <> issue.code)
          issue = Repo.get!(Issue, issue_id)

          safe =
            issue.data
            |> Map.drop(~w(related correlation_id owner_identity_id source_observation_id))
            |> Map.put("owner_identity_id", nil)
            |> Map.put("related", %{})

          Ep.Monitoring.append!(
            source,
            issue,
            actor,
            Ecto.UUID.generate(),
            Ecto.UUID.generate(),
            [{"MonitoringContentRedacted", %{"snapshot" => safe, "reason" => "erasure"}}],
            safe
          )
        end)
    end)

    {:ok, _} =
      Repo.transaction(fn ->
        if id do
          grants = from p in Ep.Monitoring.Permission, where: p.identity_id == ^id
          sources = from s in Source, where: s.identity_id == ^id
          Repo.update_all(grants, set: [status: "revoked"])
          Repo.update_all(sources, set: [status: "revoked"])
        end

        Enum.each(Repo.all(Ep.Monitoring.Rule), fn rule ->
          recipients = Enum.reject(rule.recipient_ids, &(subject_hash(&1) == hash))

          if recipients != rule.recipient_ids do
            Repo.update!(
              Ecto.Changeset.change(rule,
                recipient_ids: recipients,
                enabled: rule.enabled && recipients != []
              )
            )

            source = Repo.get!(Source, rule.source_id)

            Ep.Monitoring.Configuration.fact!(
              source,
              actor,
              Ecto.UUID.generate(),
              "MonitoringRulePrivacyRedacted",
              %{
                "rule_id" => rule.id,
                "removed_recipient_count" => length(rule.recipient_ids) - length(recipients)
              }
            )
          end
        end)

        Repo.get!(Erasure, hash)
        |> Ecto.Changeset.change(state: "live_monitoring_complete")
        |> Repo.update!()
      end)

    %{affected_events: length(event_ids), backup_status: "pending_inventory_and_sanitation"}
  end

  def retain(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -30 * 86_400, :second)

    {:ok, diagnostics} =
      Repo.transaction(fn ->
        ids =
          Repo.all(
            from d in Diagnostic, where: d.inserted_at < ^cutoff, select: d.event_id, limit: 1000
          )

        Enum.each(ids, fn id ->
          row = Repo.get!(Ep.Events.Details, id)
          Repo.update!(Ecto.Changeset.change(row, payload: Map.delete(row.payload, "diagnostic")))
        end)

        Repo.delete_all(from d in Diagnostic, where: d.event_id in ^ids)
        length(ids)
      end)

    cutoff = DateTime.add(now, -90 * 86_400, :second)

    ids =
      Repo.all(
        from e in Ep.Events.Event,
          left_join: r in Redaction,
          on: r.event_id == e.id,
          where:
            e.stream_type in ["monitoring_issue", "monitoring_configuration", "monitoring_alert"] and
              e.inserted_at < ^cutoff and is_nil(r.event_id),
          select: e.id,
          limit: 1000
      )

    actor = if ids != [], do: privacy_actor!()
    {:ok, _} = Repo.transaction(fn -> Enum.each(ids, &redact!(&1, "retention", actor)) end)
    %{diagnostics_removed: diagnostics, events_redacted: length(ids)}
  end

  def backfill do
    # Limited batches keep transactions bounded; safe to interrupt/repeat.
    query =
      from e in Ep.Events.Event,
        join: d in Ep.Events.Details,
        on: d.event_id == e.id,
        left_join: s in Subject,
        on: s.event_id == e.id,
        where:
          e.stream_type in ["monitoring_issue", "monitoring_configuration", "monitoring_alert"] and
            is_nil(s.event_id),
        select: {e, d.payload},
        limit: 500

    case Repo.all(query) do
      [] ->
        :ok

      rows ->
        {:ok, _} = Repo.transaction(fn -> Enum.each(rows, fn {e, p} -> index!(e, p) end) end)
        backfill()
    end
  end

  defp redact!(id, reason, actor) do
    event = Repo.get!(Ep.Events.Event, id)
    Events.lock!("monitoring-projector:" <> event.stream_id)

    snapshot = %{
      "privacy_erased" => true,
      "safe_message" => "Monitoring content removed under privacy/retention policy.",
      "state" => "redacted",
      "count" => 0
    }

    details = Repo.get!(Ep.Events.Details, id)

    Repo.update!(
      Ecto.Changeset.change(details, payload: %{"snapshot" => snapshot, "privacy_erased" => true})
    )

    receipt = Repo.get(Ep.Events.CommandReceipt, event.command_id)

    if receipt && String.starts_with?(receipt.command_type, "Monitoring") do
      Repo.update!(
        Ecto.Changeset.change(receipt,
          identity_id: actor,
          idempotency_key: "privacy:" <> receipt.id,
          fingerprint: :crypto.strong_rand_bytes(32),
          result: %{"status" => "privacy_erased"}
        )
      )
    end

    if event.stream_type == "monitoring_issue" do
      issue = Repo.get(Issue, event.stream_id)

      if issue && issue.version == event.stream_version && reason == "retention",
        do: Repo.update!(Ecto.Changeset.change(issue, data: snapshot))
    end

    Repo.update!(
      Ecto.Changeset.change(event,
        actor_identity_id: actor,
        command_id: Ecto.UUID.generate(),
        correlation_id: Ecto.UUID.generate()
      )
    )

    Repo.delete_all(from d in Diagnostic, where: d.event_id == ^id)
    Repo.delete_all(from v in View, where: v.id == ^id and v.kind != "issue")

    affected_views =
      from v in View,
        where:
          v.kind == "issue" and v.issue_id == ^event.stream_id and
            v.source_version <= ^event.stream_version

    Repo.update_all(affected_views, set: [data: snapshot])

    Repo.insert!(%Redaction{event_id: id, reason: reason}, on_conflict: :nothing)
  end

  defp privacy_actor! do
    {:ok, id} =
      Repo.transaction(fn ->
        Events.lock!("monitoring-privacy-actor")

        party =
          Repo.one(
            from p in Ep.Auth.Party, where: p.kind == "monitoring_privacy_service", limit: 1
          )

        if party do
          Repo.get_by!(Ep.Auth.Identity, party_id: party.id).id
        else
          party = Repo.insert!(%Ep.Auth.Party{kind: "monitoring_privacy_service"})
          Repo.insert!(%Ep.Auth.Identity{party_id: party.id}).id
        end
      end)

    id
  end

  defp references(map) when is_map(map),
    do:
      Enum.flat_map(map, fn {k, v} ->
        if k in ~w(identity_id owner_identity_id recipient_ids),
          do: List.wrap(v) |> Enum.filter(&match?({:ok, _}, Ep.Monitoring.uuid(&1))),
          else: references(v)
      end)

  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_), do: []

  defp related(map, key) when is_map(map),
    do:
      Enum.flat_map(map, fn {k, v} ->
        if k == key && match?({:ok, _}, Ep.Monitoring.uuid(v)), do: [v], else: related(v, key)
      end)

  defp related(list, key) when is_list(list), do: Enum.flat_map(list, &related(&1, key))
  defp related(_, _), do: []
end
