defmodule EpWeb.ChartOrderController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.ChartOrder

  def show(conn, p),
    do: reply(conn, ChartOrder.get(conn.assigns.current_principal, p["tenant_id"], p["book_id"]))

  def preview(conn, p),
    do:
      reply(
        conn,
        ChartOrder.preview(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id)),
          conn.assigns.backend_id
        )
      )

  def review(conn, p),
    do:
      reply(
        conn,
        ChartOrder.review(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["review_id"],
          conn.assigns.backend_id
        )
      )

  def accept(conn, p),
    do:
      reply(
        conn,
        ChartOrder.accept(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["review_id"],
          Map.drop(p, ~w(tenant_id book_id review_id)),
          List.first(get_req_header(conn, "idempotency-key")),
          conn.assigns.backend_id
        )
      )

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated ->
          401

        :not_found ->
          404

        :review_expired ->
          410

        :view_stopped ->
          503

        r
        when r in [
               :version_conflict,
               :view_pending,
               :digest_conflict,
               :invalid_review,
               :review_already_accepted,
               :idempotency_conflict,
               :catalogue_not_initialized
             ] ->
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
