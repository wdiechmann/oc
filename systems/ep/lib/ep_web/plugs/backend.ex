defmodule EpWeb.Plugs.Backend do
  @moduledoc "Protect sensitive API delivery handoff; caller identity is never supplied in the body."
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    configured = Application.get_env(:ep, :backend_tokens, %{})

    supplied =
      case get_req_header(conn, "x-ep-backend-token") do
        [value] -> value
        _ -> ""
      end

    match =
      Enum.find(configured, fn {_id, secret} ->
        is_binary(secret) && byte_size(secret) >= 32 &&
          Plug.Crypto.secure_compare(
            :crypto.hash(:sha256, supplied),
            :crypto.hash(:sha256, secret)
          )
      end)

    case match do
      {id, _} ->
        assign(conn, :backend_id, id)

      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(
          if(map_size(configured) == 0, do: 503, else: 401),
          Jason.encode!(%{error: "backend_authentication_required"})
        )
        |> halt()
    end
  end
end
