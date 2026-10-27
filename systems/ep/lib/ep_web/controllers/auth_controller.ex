defmodule EpWeb.AuthController do
  use EpWeb, :controller

  plug EpWeb.Plugs.Backend
  plug EpWeb.Plugs.Authenticate when action == :sign_out

  def request_link(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Ep.Auth.request_magic_link(params["email"], conn.assigns.backend_id) do
      {:ok, result} ->
        conn |> put_status(:accepted) |> json(result)

      {:error, :invalid_email} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_email"})

      _ ->
        conn |> put_status(:service_unavailable) |> json(%{error: "unavailable"})
    end
  end

  def request_sign_in(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Ep.Auth.request_sign_in_link(params["email"], conn.assigns.backend_id) do
      {:ok, result} ->
        conn |> put_status(:accepted) |> json(result)

      {:error, :invalid_email} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_email"})

      _ ->
        conn |> put_status(:service_unavailable) |> json(%{error: "unavailable"})
    end
  end

  def sign_out(conn, _) do
    :ok = Ep.Auth.revoke_session(conn.assigns.current_principal)
    conn |> put_resp_header("cache-control", "no-store") |> json(%{status: "signed_out"})
  end

  def verify(conn, params) do
    case Ep.Auth.verify_magic_link(params["token"], conn.assigns.backend_id) do
      {:ok, result} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{token: result.token, token_type: "Bearer", expires_at: result.expires_at})

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_token"})
    end
  end
end
