defmodule EpWeb.FormulaPreviewController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.FormulaPreview

  def show(conn, p),
    do:
      reply(
        conn,
        FormulaPreview.get(conn.assigns.current_principal, p["tenant_id"], p["book_id"])
      )

  def preview(conn, p),
    do:
      reply(
        conn,
        FormulaPreview.preview(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id))
        )
      )

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated -> 401
        :not_found -> 404
        :view_stopped -> 503
        r when r in [:view_pending, :version_conflict] -> 409
        _ -> 422
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: Atom.to_string(reason)})
  end
end
