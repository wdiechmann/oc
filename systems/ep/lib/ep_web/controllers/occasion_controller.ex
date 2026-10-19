defmodule EpWeb.OccasionController do
  use EpWeb, :controller

  def create(conn, %{"tenant_id" => tenant_id} = params) do
    key =
      case get_req_header(conn, "idempotency-key") do
        [key] -> key
        _ -> nil
      end

    case Ep.Occasions.create(conn.assigns.current_principal, tenant_id, params, key) do
      {:ok, %{result: result, replayed: replayed}} ->
        conn
        |> put_resp_header(
          "location",
          "/api/v1/tenants/#{tenant_id}/occasions/#{result["occasion_id"]}"
        )
        |> put_status(if(replayed, do: :ok, else: :created))
        |> json(Map.put(result, "replayed", replayed))

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def index(conn, %{"tenant_id" => tenant_id}),
    do: respond(conn, Ep.Occasions.list(conn.assigns.current_principal, tenant_id))

  def show(conn, %{"tenant_id" => tenant_id, "id" => id}),
    do: respond(conn, Ep.Occasions.get(conn.assigns.current_principal, tenant_id, id))

  defp respond(conn, {:ok, %{status: :pending} = result}),
    do: conn |> put_status(:accepted) |> put_resp_header("retry-after", "1") |> json(result)

  defp respond(conn, {:ok, result}), do: json(conn, result)
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, reason) do
    status =
      case reason do
        :not_found -> :not_found
        :unauthenticated -> :unauthorized
        :view_stopped -> :service_unavailable
        r when r in [:slug_taken, :idempotency_conflict] -> :conflict
        _ -> :unprocessable_entity
      end

    conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
  end
end
