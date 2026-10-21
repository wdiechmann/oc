defmodule EpWeb.RecruitmentController do
  use EpWeb, :controller

  def manage(conn, %{"tenant_id" => tid, "occasion_id" => oid}),
    do: reply(conn, Ep.Recruitment.manage(conn.assigns.current_principal, tid, oid))

  def open(conn, %{"tenant_id" => tid, "occasion_id" => oid} = p),
    do: reply(conn, Ep.Recruitment.open(conn.assigns.current_principal, tid, oid, p, key(conn)))

  def close(conn, %{"tenant_id" => tid, "occasion_id" => oid} = p),
    do: reply(conn, Ep.Recruitment.close(conn.assigns.current_principal, tid, oid, p, key(conn)))

  def submit(conn, %{"tenant_id" => tid, "occasion_id" => oid} = p),
    do:
      reply(
        conn,
        Ep.Recruitment.submit(conn.assigns.current_principal, tid, oid, p, key(conn)),
        :created
      )

  def applications(conn, %{"tenant_id" => tid, "occasion_id" => oid}),
    do: reply(conn, Ep.Recruitment.applications(conn.assigns.current_principal, tid, oid))

  def landing(conn, %{"tenant_id" => tid, "slug" => slug}),
    do: reply(conn, Ep.Recruitment.landing(tid, slug))

  defp key(conn), do: List.first(get_req_header(conn, "idempotency-key"))

  defp reply(conn, result, success \\ :ok) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case result do
      {:ok, %{result: r, replayed: replayed}} ->
        conn
        |> put_status(if(replayed, do: :ok, else: success))
        |> json(Map.put(r, "replayed", replayed))

      {:ok, %{status: :pending} = r} ->
        conn |> put_status(:accepted) |> put_resp_header("retry-after", "1") |> json(r)

      {:ok, r} ->
        json(conn, r)

      {:error, reason} ->
        status =
          case reason do
            :not_found ->
              :not_found

            :unauthenticated ->
              :unauthorized

            :view_stopped ->
              :service_unavailable

            r
            when r in [
                   :already_open,
                   :already_closed,
                   :already_applied,
                   :recruitment_closed,
                   :occasion_expired,
                   :policy_changed,
                   :idempotency_conflict
                 ] ->
              :conflict

            _ ->
              :unprocessable_entity
          end

        conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
    end
  end
end
