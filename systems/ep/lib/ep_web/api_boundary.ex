defmodule EpWeb.ApiBoundary do
  @moduledoc "Bounded correlation context and safe unexpected-failure capture around the router."
  import Plug.Conn
  def init(opts), do: EpWeb.Router.init(opts)

  def call(conn, opts) do
    supplied =
      case get_req_header(conn, "x-correlation-id") do
        [value] -> value
        _ -> nil
      end

    id =
      case Ep.Monitoring.uuid(supplied) do
        {:ok, uuid} -> uuid
        _ -> Ecto.UUID.generate()
      end

    previous = Process.get(:ep_correlation_id)
    Process.put(:ep_correlation_id, id)
    conn = conn |> assign(:correlation_id, id) |> put_resp_header("x-correlation-id", id)

    try do
      EpWeb.Router.call(conn, opts)
    rescue
      error ->
        # Expected HTTP exceptions preserve their normal status and framework handling.
        if Plug.Exception.status(error) < 500, do: reraise(error, __STACKTRACE__)

        Ep.Monitoring.capture_exception(
          id,
          String.starts_with?(conn.request_path, "/api/v1/monitoring")
        )

        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{error: "internal_error", correlation_id: id, outcome: "unknown"})
        )
    after
      if previous,
        do: Process.put(:ep_correlation_id, previous),
        else: Process.delete(:ep_correlation_id)
    end
  end
end
