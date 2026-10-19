defmodule EpWeb.TenantController do
  use EpWeb, :controller

  def create(conn, params) do
    key =
      case get_req_header(conn, "idempotency-key") do
        [key] -> key
        _ -> nil
      end

    case Ep.Tenancy.create_tenant(conn.assigns.current_principal, params, key) do
      {:ok, %{result: result, replayed: replayed}} ->
        conn
        |> put_status(if(replayed, do: :ok, else: :created))
        |> put_resp_header("location", "/api/v1/tenants/" <> result["tenant_id"])
        |> json(Map.put(result, "replayed", replayed))

      {:error, :unauthenticated} ->
        error(conn, :unauthorized, "unauthenticated")

      {:error, :idempotency_conflict} ->
        error(conn, :conflict, "idempotency_conflict")

      {:error, reason} ->
        error(conn, :unprocessable_entity, Atom.to_string(reason))
    end
  end

  def show(conn, %{"id" => id}) do
    case Ep.Tenancy.get_tenant(conn.assigns.current_principal, id) do
      {:ok, %{status: :pending} = result} ->
        conn |> put_status(:accepted) |> put_resp_header("retry-after", "1") |> json(result)

      {:ok, result} ->
        json(conn, result)

      {:error, :unauthenticated} ->
        error(conn, :unauthorized, "unauthenticated")

      {:error, :view_stopped} ->
        error(conn, :service_unavailable, "view_stopped")

      {:error, :not_found} ->
        error(conn, :not_found, "not_found")
    end
  end

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
