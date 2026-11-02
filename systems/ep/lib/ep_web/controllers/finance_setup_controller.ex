defmodule EpWeb.FinanceSetupController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.Setup

  def show(conn, p),
    do: reply(conn, Setup.get(conn.assigns.current_principal, p["tenant_id"], p["book_id"]))

  def accounts(conn, p),
    do:
      reply(
        conn,
        Setup.accounts(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ["tenant_id", "book_id"])
        )
      )

  def catalogues(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.Catalogues.get(conn.assigns.current_principal, p["tenant_id"], p["book_id"])
      )

  def initialize_catalogues(conn, p), do: command(conn, p, "catalogue_initialize")
  def create_catalogue_entry(conn, p), do: command(conn, p, "catalogue_create")
  def revise_catalogue_entry(conn, p), do: command(conn, p, "catalogue_revise")

  def steward(conn, p), do: command(conn, p, "steward")
  def reopening_authority(conn, p), do: command(conn, p, "reopening_authority")
  def binding(conn, p), do: command(conn, p, "binding")
  def create_account(conn, p), do: command(conn, p, "account_create")
  def revise_account(conn, p), do: command(conn, p, "account_revise")

  defp command(conn, p, action) do
    reply(
      conn,
      Setup.command(
        conn.assigns.current_principal,
        p["tenant_id"],
        p["book_id"],
        action,
        Map.drop(p, ["tenant_id", "book_id"]),
        List.first(get_req_header(conn, "idempotency-key")),
        conn.assigns.backend_id
      )
    )
  end

  defp reply(conn, {:ok, data}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(data)

  defp reply(conn, {:error, reason}) do
    status =
      case reason do
        :unauthenticated ->
          401

        :not_found ->
          404

        :view_stopped ->
          503

        r
        when r in [
               :version_conflict,
               :number_taken,
               :binding_taken,
               :idempotency_conflict,
               :position_taken,
               :chart_changed,
               :catalogues_initialized,
               :catalogue_not_initialized
             ] ->
          409

        _ ->
          422
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: Atom.to_string(reason)})
  end
end
