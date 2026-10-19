defmodule EpWeb.AuthController do
  use EpWeb, :controller

  def request_link(conn, params) do
    case Ep.Auth.request_magic_link(params["email"]) do
      :ok ->
        conn |> put_status(:accepted) |> json(%{status: "check_your_email"})

      {:error, :invalid_email} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_email"})

      _ ->
        conn |> put_status(:service_unavailable) |> json(%{error: "delivery_unavailable"})
    end
  end

  def verify(conn, params) do
    case Ep.Auth.verify_magic_link(params["token"]) do
      {:ok, result} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{token: result.token, token_type: "Bearer", expires_at: result.expires_at})

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_token"})
    end
  end
end
