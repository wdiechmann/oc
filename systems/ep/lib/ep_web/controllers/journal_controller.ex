defmodule EpWeb.JournalController do
  use EpWeb, :controller
  plug EpWeb.Plugs.Backend
  alias Ep.Finance.Journals

  def index(conn, p),
    do:
      reply(
        conn,
        Journals.get(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id))
        )
      )

  def review(conn, p),
    do:
      reply(
        conn,
        Journals.review(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id)),
          conn.assigns.backend_id
        )
      )

  def show_review(conn, p),
    do:
      reply(
        conn,
        Journals.get_review(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["review_id"],
          conn.assigns.backend_id
        )
      )

  def accept(conn, p),
    do:
      reply(
        conn,
        Journals.accept(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id)),
          List.first(get_req_header(conn, "idempotency-key")),
          conn.assigns.backend_id
        )
      )

  def work(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.save(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["mode"],
          Map.drop(p, ~w(tenant_id book_id mode)),
          List.first(get_req_header(conn, "idempotency-key")),
          conn.assigns.backend_id
        )
      )

  def lookup(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.lookup(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["q"]
        )
      )

  def preview_row(conn, p),
    do:
      reply(
        conn,
        Journals.preview_row(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          Map.drop(p, ~w(tenant_id book_id))
        )
      )

  def attachments(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.attachments(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["row_id"]
        )
      )

  def stage(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.stage(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["row_id"],
          Map.drop(p, ~w(tenant_id book_id row_id)),
          conn.assigns.backend_id
        )
      )

  def staged_preview(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.staged_preview(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["row_id"],
          p["upload_id"],
          conn.assigns.backend_id
        )
      )

  def download(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalWork.download(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["attachment_id"]
        )
      )

  def posting_impact(conn, p),
    do:
      reply(
        conn,
        Ep.Finance.JournalPosting.impact(
          conn.assigns.current_principal,
          p["tenant_id"],
          p["book_id"],
          p["draft_id"]
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

        :review_expired ->
          410

        :view_stopped ->
          503

        r
        when r in [
               :version_conflict,
               :view_pending,
               :digest_conflict,
               :idempotency_conflict,
               :review_already_accepted
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
