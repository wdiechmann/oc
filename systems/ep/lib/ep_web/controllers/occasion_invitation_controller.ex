defmodule EpWeb.OccasionInvitationController do
  use EpWeb, :controller

  def create(conn, %{"tenant_id" => tid, "occasion_id" => oid} = params),
    do:
      reply(
        conn,
        Ep.Invitations.invite(conn.assigns.current_principal, tid, params, key(conn), oid),
        :created
      )

  def index(conn, %{"tenant_id" => tid, "occasion_id" => oid}),
    do: reply(conn, Ep.Invitations.list_for_tenant(conn.assigns.current_principal, tid, oid), :ok)

  def revoke(conn, %{"tenant_id" => tid, "occasion_id" => oid, "id" => id}),
    do:
      reply(
        conn,
        Ep.Invitations.revoke(conn.assigns.current_principal, tid, id, key(conn), oid),
        :ok
      )

  def accept(conn, %{"tenant_id" => tid, "occasion_id" => oid, "id" => id}),
    do:
      reply(
        conn,
        Ep.Invitations.accept(conn.assigns.current_principal, tid, id, key(conn), oid),
        :ok
      )

  def incoming(conn, _),
    do: reply(conn, Ep.Invitations.incoming_occasions(conn.assigns.current_principal), :ok)

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
            :not_found ->
              :not_found

            :unauthenticated ->
              :unauthorized

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
