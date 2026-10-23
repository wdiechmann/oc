defmodule Ep.Monitoring.Queries do
  @moduledoc "Current-authority checked monitoring MVs and private command reconciliation."
  import Ecto.Query
  alias Ep.{Auth, Monitoring, Repo}
  alias Ep.Monitoring.{Issue, Pending, Source, View}

  @filters ~w(issue_id occasion_id code severity state application correlation_id limit cursor cutoff)

  def list(principal, tid, kind, params) do
    with {:ok, tid} <- Monitoring.uuid(tid), {:ok, opts} <- options(params) do
      Repo.transaction(fn ->
        Monitoring.authorize!(principal, tid, opts.occasion_id)
        control!(tid)

        query =
          from v in View,
            where:
              v.tenant_id == ^tid and
                v.kind in ^if(kind == "timeline", do: ["observation", "lifecycle"], else: [kind]) and
                v.inserted_at <= ^opts.cutoff

        query =
          if opts.issue_id, do: from(v in query, where: v.issue_id == ^opts.issue_id), else: query

        query =
          if opts.occasion_id,
            do: from(v in query, where: v.occasion_id == ^opts.occasion_id),
            else: query

        query =
          Enum.reduce(opts.filters, query, fn {key, value}, q ->
            from v in q, where: fragment("? ->> ? = ?", v.data, ^key, ^value)
          end)

        query =
          if opts.cursor,
            do:
              from(v in query,
                where:
                  v.inserted_at < ^elem(opts.cursor, 0) or
                    (v.inserted_at == ^elem(opts.cursor, 0) and v.id < ^elem(opts.cursor, 1))
              ),
            else: query

        rows =
          Repo.all(
            from v in query, order_by: [desc: v.inserted_at, desc: v.id], limit: ^(opts.limit + 1)
          )

        items = Enum.take(rows, opts.limit)

        next =
          if length(rows) > opts.limit,
            do: encode_cursor(List.last(items), opts.cutoff),
            else: nil

        %{
          items: Enum.map(items, &serialize/1),
          next_cursor: next,
          cutoff: opts.cutoff,
          freshness: freshness(tid, opts.occasion_id)
        }
      end)
    else
      _ -> {:error, :invalid_query}
    end
  end

  def detail(principal, tid, id) do
    with {:ok, tid} <- Monitoring.uuid(tid), {:ok, id} <- Monitoring.uuid(id) do
      Repo.transaction(fn ->
        issue = Repo.get(Issue, id) || Repo.rollback(:not_found)
        source = Repo.get!(Source, issue.source_id)
        unless source.tenant_id == tid, do: Repo.rollback(:not_found)
        Monitoring.authorize!(principal, tid, source.occasion_id)
        control!(tid)

        case Repo.get(View, id) do
          nil ->
            %{status: "pending", issue_id: id, expected_version: issue.version}

          row ->
            %{
              status: if(row.source_version == issue.version, do: "ready", else: "pending"),
              issue: serialize(row),
              expected_version: issue.version,
              freshness: freshness(tid, source.occasion_id)
            }
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  # A receipt exists only for accepted commands. Absence is unknown, never evidence of failure.
  def command(principal, params) do
    Repo.transaction(fn ->
      Auth.lock_principal!(principal)

      receipt =
        case params do
          %{"id" => id} ->
            case Monitoring.uuid(id) do
              {:ok, id} ->
                Repo.get_by(Ep.Events.CommandReceipt, id: id, identity_id: principal.identity_id)

              _ ->
                nil
            end

          %{"command_type" => type, "idempotency_key" => key}
          when is_binary(type) and is_binary(key) and byte_size(type) <= 200 and
                 byte_size(key) <= 128 ->
            Repo.get_by(Ep.Events.CommandReceipt,
              identity_id: principal.identity_id,
              command_type: type,
              idempotency_key: key
            )

          _ ->
            Repo.rollback(:invalid_query)
        end

      if receipt do
        # Only return receipt facts that belong to a currently authorized context.
        event = Repo.one(from e in Ep.Events.Event, where: e.command_id == ^receipt.id, limit: 1)

        if event && event.tenant_id,
          do: Monitoring.authorize!(principal, event.tenant_id, event.occasion_id)

        %{
          status: "accepted",
          command_id: receipt.id,
          command_type: receipt.command_type,
          result: receipt.result
        }
      else
        %{status: "unknown"}
      end
    end)
  end

  defp control!(tid) do
    row =
      Repo.one(
        from c in Ep.Projections.Control,
          where: c.tenant_id == ^tid and c.name == "monitoring",
          lock: "FOR SHARE"
      )

    if row && row.state != "running", do: Repo.rollback(:view_stopped)
  end

  defp freshness(tid, oid) do
    pending =
      from p in Pending,
        join: e in Ep.Events.Event,
        on: e.id == p.event_id,
        where: e.tenant_id == ^tid

    pending = if oid, do: from([p, e] in pending, where: e.occasion_id == ^oid), else: pending

    %{
      pending_events: Repo.aggregate(pending, :count),
      oldest_pending_at: Repo.aggregate(pending, :min, :inserted_at),
      checked_at: DateTime.utc_now()
    }
  end

  defp serialize(row),
    do: %{
      id: row.id,
      issue_id: row.issue_id,
      occasion_id: row.occasion_id,
      source_version: row.source_version,
      updated_at: row.updated_at,
      data: row.data
    }

  defp options(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @filters)),
         {:ok, oid} <- optional_uuid(params["occasion_id"]),
         {:ok, issue_id} <- optional_uuid(params["issue_id"]),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, cursor, cutoff} <- cursor(params["cursor"], params["cutoff"]),
         filters = Map.take(params, ~w(code severity state application correlation_id)),
         true <- Enum.all?(filters, fn {_k, v} -> is_binary(v) and byte_size(v) in 1..128 end) do
      {:ok,
       %{
         issue_id: issue_id,
         occasion_id: oid,
         limit: limit,
         cursor: cursor,
         cutoff: cutoff,
         filters: filters
       }}
    else
      _ -> :error
    end
  end

  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(v), do: Monitoring.uuid(v)
  defp limit(nil), do: {:ok, 50}

  defp limit(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} when i in 1..100 -> {:ok, i}
      _ -> :error
    end
  end

  defp limit(_), do: :error
  defp cursor(nil, nil), do: {:ok, nil, DateTime.utc_now()}

  defp cursor(nil, cutoff) when is_binary(cutoff) do
    case DateTime.from_iso8601(cutoff) do
      {:ok, dt, 0} -> {:ok, nil, dt}
      _ -> :error
    end
  end

  defp cursor(encoded, _) when is_binary(encoded) and byte_size(encoded) < 1024 do
    with {:ok, bytes} <- Base.url_decode64(encoded, padding: false),
         {:ok, %{"id" => id, "time" => time, "cutoff" => cutoff}} <- Jason.decode(bytes),
         {:ok, id} <- Monitoring.uuid(id),
         true <- is_binary(time) and is_binary(cutoff),
         {:ok, time, 0} <- DateTime.from_iso8601(time),
         {:ok, cutoff, 0} <- DateTime.from_iso8601(cutoff) do
      {:ok, {time, id}, cutoff}
    else
      _ -> :error
    end
  end

  defp cursor(_, _), do: :error

  defp encode_cursor(row, cutoff),
    do:
      Base.url_encode64(Jason.encode!(%{id: row.id, time: row.inserted_at, cutoff: cutoff}),
        padding: false
      )
end
