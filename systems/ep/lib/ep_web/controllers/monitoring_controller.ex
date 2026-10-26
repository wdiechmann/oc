defmodule EpWeb.MonitoringController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend when action in [:record, :delivery, :catalogue]

  def record(conn, params),
    do: record_result(conn, Ep.Monitoring.record(conn.assigns.backend_id, params))

  def delivery(conn, params),
    do: record_result(conn, Ep.Monitoring.record(conn.assigns.backend_id, params, true))

  def catalogue(conn, _),
    do: reply(conn, {:ok, %{schema_version: 1, codes: Ep.Monitoring.Catalogue.entries()}})

  def issues(conn, %{"tenant_id" => tid} = params), do: list(conn, tid, "issue", params)

  def observations(conn, %{"tenant_id" => tid} = params),
    do: list(conn, tid, "observation", params)

  def timeline(conn, %{"tenant_id" => tid} = params), do: list(conn, tid, "timeline", params)

  def detail(conn, %{"tenant_id" => tid, "id" => id}),
    do: reply(conn, Ep.Monitoring.Queries.detail(conn.assigns.current_principal, tid, id))

  def command(conn, params),
    do: reply(conn, Ep.Monitoring.Queries.command(conn.assigns.current_principal, params))

  def update_issue(conn, %{"tenant_id" => tid, "id" => id} = params) do
    key =
      case get_req_header(conn, "idempotency-key") do
        [value] -> value
        _ -> nil
      end

    reply(
      conn,
      Ep.Monitoring.action(
        conn.assigns.current_principal,
        tid,
        id,
        Map.drop(params, ["tenant_id", "id"]),
        key
      )
    )
  end

  defp list(conn, tid, kind, params),
    do:
      reply(
        conn,
        Ep.Monitoring.Queries.list(
          conn.assigns.current_principal,
          tid,
          kind,
          Map.delete(params, "tenant_id")
        )
      )

  defp record_result(conn, {:ok, result}),
    do: conn |> put_status(if(result["replayed"], do: 200, else: 201)) |> reply({:ok, result})

  defp record_result(conn, error), do: reply(conn, error)

  defp reply(conn, {:ok, result}) do
    conn = conn |> put_resp_header("cache-control", "no-store")

    conn =
      if result[:status] == "pending",
        do: conn |> put_status(202) |> put_resp_header("retry-after", "1"),
        else: conn

    json(conn, result)
  end

  defp reply(conn, {:error, reason}) do
    conn = if reason == :rate_limited, do: put_resp_header(conn, "retry-after", "60"), else: conn

    status =
      case reason do
        :rate_limited -> 429
        :unauthenticated -> 401
        :not_found -> 404
        :privacy_cleanup_pending -> 503
        :view_stopped -> 503
        r when r in [:idempotency_conflict, :version_conflict] -> 409
        _ -> 422
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: Atom.to_string(reason)})
  end
end
