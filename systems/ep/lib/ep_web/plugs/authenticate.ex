defmodule EpWeb.Plugs.Authenticate do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, principal} <- Ep.Auth.authenticate(token) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> assign(:current_principal, principal)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthenticated"}))
        |> halt()
    end
  end
end
