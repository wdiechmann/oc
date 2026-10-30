defmodule EpWeb.PeriodController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.Periods

  def index(conn, p),
    do: reply(conn, Periods.list(conn.assigns.current_principal, p["tenant_id"], p["book_id"]))

  def create(conn, p), do: command(conn, p, "create")
  def revise(conn, p), do: command(conn, p, "revise")
  def open(conn, p), do: command(conn, p, "open")
  def close(conn, p), do: command(conn, p, "close")
  def reopen(conn, p), do: command(conn, p, "reopen")

  defp command(conn, p, action) do
    reply(
      conn,
      Periods.command(
        conn.assigns.current_principal,
        p["tenant_id"],
        p["book_id"],
        action,
        Map.drop(p, ["tenant_id", "book_id"]),
        List.first(get_req_header(conn, "idempotency-key")),
        conn.assigns.backend_id
      )
    )
  end

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated ->
          401

        :not_found ->
          404

        :view_stopped ->
          503

        r
        when r in [:version_conflict, :period_overlap, :invalid_transition, :idempotency_conflict] ->
          409

        _ ->
          422
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: Atom.to_string(reason)})
  end
end
