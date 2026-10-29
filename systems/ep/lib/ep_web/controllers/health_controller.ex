defmodule EpWeb.HealthController do
  use EpWeb, :controller

  @required_tables ~w(public.oban_jobs public.party public.identity public.magic_link
    public.identity_session public.tenant public.tenant_access public.command_receipt
    public.stream_head public.event public.event_details public.outbox public.consumer_inbox
    public.mv_control public.tenant_directory public.occasion public.occasion_admin public.occasion_directory public.tenant_admin_invitation public.recruitment_application public.monitoring_source public.monitoring_issue public.monitoring_pending public.monitoring_view public.finance_book public.finance_book_view public.monitoring_rule public.monitoring_alert public.monitoring_permission public.monitoring_diagnostic public.monitoring_subject public.monitoring_erasure public.monitoring_redaction)

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
