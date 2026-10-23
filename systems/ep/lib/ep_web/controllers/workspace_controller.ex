defmodule EpWeb.WorkspaceController do
  use EpWeb, :controller

  def index(conn, _) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Ep.Workspaces.list(conn.assigns.current_principal) do
      {:ok, result} ->
        json(conn, result)

      {:error, :unauthenticated} ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthenticated"})
    end
  end
end
