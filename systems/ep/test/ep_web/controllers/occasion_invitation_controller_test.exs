defmodule EpWeb.OccasionInvitationControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  test "occasion routes bind the grant and reject tenant-route and sibling acceptance", %{
    conn: conn
  } do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "SL"}, "tenant")
    tid = t["tenant_id"]

    {:ok, %{result: o}} =
      Ep.Occasions.create(
        owner.principal,
        tid,
        %{"name" => "SL2030", "slug" => "sl2030", "expires_at" => "2032-01-01T00:00:00Z"},
        "occasion"
      )

    oid = o["occasion_id"]

    admin =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "invite")

    result =
      json_response(
        post(admin, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations", %{
          "email" => "occasion@example.test",
          "role" => "tenant_admin",
          "status" => "accepted"
        }),
        201
      )

    iid = result["invitation_id"]
    assert result["occasion_id"] == oid && result["status"] == "pending"

    assert json_response(get(admin, ~p"/api/v1/tenants/#{tid}/admin-invitations"), 200)[
             "invitations"
           ] == []

    assert length(
             json_response(
               get(admin, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations"),
               200
             )["invitations"]
           ) == 1

    prospect = sign_in("occasion@example.test")

    recipient =
      build_conn()
      |> put_req_header("x-ep-backend-token", String.duplicate("b", 48))
      |> put_req_header("authorization", "Bearer " <> prospect.token)
      |> put_req_header("idempotency-key", "accept")

    assert json_response(
             post(recipient, ~p"/api/v1/tenants/#{tid}/admin-invitations/#{iid}/accept"),
             404
           )["error"] == "not_found"

    assert json_response(
             post(
               recipient,
               ~p"/api/v1/tenants/#{tid}/occasions/#{Ecto.UUID.generate()}/admin-invitations/#{iid}/accept"
             ),
             404
           )["error"] == "not_found"

    assert json_response(
             post(
               recipient,
               ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations/#{iid}/accept"
             ),
             200
           )["status"] == "accepted"

    assert json_response(get(recipient, ~p"/api/v1/tenants/#{tid}"), 404)["error"] == "not_found"
    Oban.drain_queue(queue: :projections)

    assert json_response(get(recipient, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}"), 200)[
             "can_manage_admins"
           ] == false

    assert length(
             json_response(get(recipient, ~p"/api/v1/me/occasion-admin-invitations"), 200)[
               "invitations"
             ]
           ) == 1

    assert json_response(
             post(recipient, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations", %{
               "email" => "escalate@example.test"
             }),
             404
           )["error"] == "not_found"
  end
end
