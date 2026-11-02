defmodule EpWeb.ChartImportController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.ChartImports

  def info(conn, p),
    do:
      reply(conn, ChartImports.info(conn.assigns.current_principal, p["tenant_id"], p["book_id"]))

  def export(conn, p),
    do:
      reply(
        conn,
        ChartImports.export(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ["tenant_id", "book_id"])
        )
      )

  def upload(conn, p),
    do:
      reply(
        conn,
        ChartImports.upload(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ["tenant_id", "book_id"]),
          conn.assigns.backend_id
        )
      )

  def show(conn, p),
    do:
      reply(
        conn,
        ChartImports.get(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["import_id"],
          conn.assigns.backend_id
        )
      )

  def preview(conn, p),
    do:
      reply(
        conn,
        ChartImports.preview(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["import_id"],
          Map.drop(p, ["tenant_id", "book_id", "import_id"]),
          conn.assigns.backend_id
        )
      )

  def accept(conn, p),
    do:
      reply(
        conn,
        ChartImports.accept(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["import_id"],
          Map.drop(p, ["tenant_id", "book_id", "import_id"]),
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
               :chart_changed,
               :digest_conflict,
               :invalid_review,
               :import_already_accepted,
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
