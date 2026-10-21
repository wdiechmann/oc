defmodule EpWeb.HealthController do
  use EpWeb, :controller

  @required_tables ~w(public.oban_jobs public.party public.identity public.magic_link
    public.identity_session public.tenant public.tenant_access public.command_receipt
    public.stream_head public.event public.event_details public.outbox public.consumer_inbox
    public.mv_control public.tenant_directory public.occasion public.occasion_admin public.occasion_directory public.tenant_admin_invitation public.recruitment_application)

  @doc "Liveness does not depend on PostgreSQL or any external service."
  def live(conn, _params), do: json(conn, %{status: "ok"})

  @doc "Readiness requires EP tables, the queue table and the Oban supervisor."
  def ready(conn, _params) do
    if ready?() do
      json(conn, %{status: "ready"})
    else
      conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end

  defp ready? do
    case Ecto.Adapters.SQL.query(
           Ep.Repo,
           "SELECT bool_and(to_regclass(name) IS NOT NULL) FROM unnest($1::text[]) AS required(name)",
           [@required_tables],
           timeout: 1_000,
           pool_timeout: 1_000
         ) do
      {:ok, %{rows: [[true]]}} -> is_pid(Oban.whereis(Oban))
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
