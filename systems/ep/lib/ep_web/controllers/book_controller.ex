defmodule EpWeb.BookController do
  use EpWeb, :controller
  alias Ep.Finance.Books
  def index(conn, p), do: reply(conn, Books.list(conn.assigns.current_principal, p["tenant_id"]))

  def show(conn, p),
    do: reply(conn, Books.get(conn.assigns.current_principal, p["tenant_id"], p["id"]))

  def create(conn, p),
    do:
      reply(
        conn,
        Books.create(
          conn.assigns.current_principal,
          p["tenant_id"],
          Map.drop(p, ["tenant_id"]),
          key(conn)
        )
      )

  def update(conn, p),
    do:
      reply(
        conn,
        Books.revise(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["id"],
          Map.drop(p, ["tenant_id", "id"]),
          key(conn)
        )
      )

  defp key(conn), do: List.first(get_req_header(conn, "idempotency-key"))

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated ->
          401

        :not_found ->
          404

        r when r in [:code_taken, :version_conflict, :idempotency_conflict, :hierarchy_cycle] ->
          409

        :view_stopped ->
          503

        _ ->
          422
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: Atom.to_string(reason)})
  end
end
