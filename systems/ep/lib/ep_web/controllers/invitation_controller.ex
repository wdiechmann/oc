defmodule EpWeb.InvitationController do
  use EpWeb, :controller

  def create(conn, %{"tenant_id" => tenant_id} = params),
    do:
      reply(
        conn,
        Ep.Invitations.invite(conn.assigns.current_principal, tenant_id, params, key(conn)),
        :created
      )

  def revoke(conn, %{"tenant_id" => tenant_id, "id" => id}),
    do:
      reply(
        conn,
        Ep.Invitations.revoke(conn.assigns.current_principal, tenant_id, id, key(conn)),
        :ok
      )

  def accept(conn, %{"tenant_id" => tenant_id, "id" => id}),
    do:
      reply(
        conn,
        Ep.Invitations.accept(conn.assigns.current_principal, tenant_id, id, key(conn)),
        :ok
      )

  def index(conn, %{"tenant_id" => tenant_id}),
    do:
      reply(conn, Ep.Invitations.list_for_tenant(conn.assigns.current_principal, tenant_id), :ok)

  def incoming(conn, _),
    do: reply(conn, Ep.Invitations.incoming(conn.assigns.current_principal), :ok)

  defp key(conn), do: List.first(get_req_header(conn, "idempotency-key"))

  defp reply(conn, result, status) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case result do
      {:ok, %{result: result, replayed: replayed}} ->
        conn
        |> put_status(if(replayed, do: :ok, else: status))
        |> json(Map.put(result, "replayed", replayed))

      {:ok, result} ->
        json(conn, result)

      {:error, reason} ->
        status =
          case reason do
            :unauthenticated ->
              :unauthorized

            :not_found ->
              :not_found

            r
            when r in [
                   :idempotency_conflict,
                   :already_invited,
                   :already_admin,
                   :invitation_unavailable
                 ] ->
              :conflict

            _ ->
              :unprocessable_entity
          end

        conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
    end
  end
end
