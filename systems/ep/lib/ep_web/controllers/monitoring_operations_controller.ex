defmodule EpWeb.MonitoringOperationsController do
  use EpWeb, :controller
  alias Ep.Monitoring.{Configuration, Alerts}
  plug EpWeb.Plugs.Backend when action in [:bindings, :claim, :outcome]
  def bindings(conn, _), do: reply(conn, Configuration.bindings(conn.assigns.backend_id))

  def sources(conn, p),
    do:
      reply(
        conn,
        Configuration.sources(conn.assigns.current_principal, p["tenant_id"], p["occasion_id"])
      )

  def register(conn, p),
    do:
      reply(
        conn,
        Configuration.register(
          conn.assigns.current_principal,
          p["tenant_id"],
          Map.drop(p, ["tenant_id"]),
          key(conn)
        )
      )

  def revoke(conn, p),
    do:
      reply(
        conn,
        Configuration.revoke(conn.assigns.current_principal, p["tenant_id"], p["id"], key(conn))
      )

  def assignees(conn, p),
    do:
      reply(
        conn,
        Configuration.assignees(conn.assigns.current_principal, p["tenant_id"], p["occasion_id"])
      )

  def rules(conn, p),
    do:
      reply(conn, Alerts.rules(conn.assigns.current_principal, p["tenant_id"], p["occasion_id"]))

  def configure(conn, p),
    do:
      reply(
        conn,
        Alerts.configure(
          conn.assigns.current_principal,
          p["tenant_id"],
          Map.drop(p, ["tenant_id"]),
          key(conn)
        )
      )

  def suppress(conn, p),
    do:
      reply(
        conn,
        Alerts.suppress(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["id"],
          Map.drop(p, ["tenant_id", "id"]),
          key(conn)
        )
      )

  def rule_state(conn, p),
    do:
      reply(
        conn,
        Alerts.set_enabled(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["id"],
          Map.drop(p, ["tenant_id", "id"]),
          key(conn)
        )
      )

  def alerts(conn, p),
    do:
      reply(
        conn,
        Alerts.statuses(conn.assigns.current_principal, p["tenant_id"], p["occasion_id"])
      )

  def claim(conn, p), do: reply(conn, Alerts.claim(conn.assigns.backend_id, p))

  def outcome(conn, p),
    do: reply(conn, Alerts.outcome(conn.assigns.backend_id, p["id"], Map.delete(p, "id")))

  def diagnostic(conn, p),
    do:
      reply(
        conn,
        Ep.Monitoring.Diagnostics.read(conn.assigns.current_principal, p["tenant_id"], p["id"])
      )

  def platform_issues(conn, p),
    do: reply(conn, Ep.Monitoring.Queries.list(conn.assigns.current_principal, nil, "issue", p))

  def platform_observations(conn, p),
    do:
      reply(
        conn,
        Ep.Monitoring.Queries.list(conn.assigns.current_principal, nil, "observation", p)
      )

  def platform_detail(conn, p),
    do: reply(conn, Ep.Monitoring.Queries.detail(conn.assigns.current_principal, nil, p["id"]))

  def platform_timeline(conn, p),
    do:
      reply(conn, Ep.Monitoring.Queries.list(conn.assigns.current_principal, nil, "timeline", p))

  def access(conn, _) do
    reply(
      conn,
      Ep.Repo.transaction(fn ->
        Ep.Auth.lock_principal!(conn.assigns.current_principal)
        import Ecto.Query

        granted =
          Ep.Repo.exists?(
            from a in Ep.Monitoring.Permission,
              where:
                a.identity_id == ^conn.assigns.current_principal.identity_id and
                  a.scope_key == "global" and a.permission == "platform_monitor" and
                  a.status == "active"
          )

        %{platform_monitor: granted}
      end)
    )
  end

  defp key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [v] -> v
      _ -> nil
    end
  end

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated -> 401
        :not_found -> 404
        r when r in [:version_conflict, :idempotency_conflict] -> 409
        :privacy_cleanup_pending -> 503
        :view_stopped -> 503
        _ -> 422
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: Atom.to_string(reason)})
  end
end
