defmodule EpWeb.VatRuleController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.{VatRules, Setup}

  def index(conn, p),
    do: reply(conn, VatRules.get(conn.assigns.current_principal, p["tenant_id"], p["book_id"]))

  def create(conn, p), do: command(conn, p, "vat_rule_create")
  def update(conn, p), do: command(conn, p, "vat_rule_revise")

  def quote(conn, p),
    do:
      reply(
        conn,
        VatRules.quote(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["vat_entry_id"],
          p["date"],
          integer(p["net_minor"]),
          if(Map.has_key?(p, "assessed_vat_minor"),
            do: integer(p["assessed_vat_minor"]) || :invalid
          )
        )
      )

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp command(conn, p, action),
    do:
      reply(
        conn,
        Setup.command(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          action,
          Map.drop(p, ~w(tenant_id book_id)),
          List.first(get_req_header(conn, "idempotency-key")),
          conn.assigns.backend_id
        )
      )

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
               :vat_rule_overlap,
               :idempotency_conflict,
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
