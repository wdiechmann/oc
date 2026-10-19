defmodule EpWeb.InvitationControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  test "HTTP invitation requires verified intended identity and acceptance, never client roles",
       %{conn: conn} do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "SL"}, "tenant")
    tid = t["tenant_id"]

    admin =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "invite")

    invited =
      post(admin, ~p"/api/v1/tenants/#{tid}/admin-invitations", %{
        "email" => "prospect@example.test",
        "role" => "platform_superuser",
        "status" => "accepted"
      })

    r = json_response(invited, 201)
    iid = r["invitation_id"]
    assert get_resp_header(invited, "cache-control") == ["no-store"]
    assert r["status"] == "pending"

    assert json_response(get(admin, ~p"/api/v1/tenants/#{tid}/admin-invitations"), 200)[
             "invitations"
           ]
           |> length() == 1

    wrong = sign_in()

    foreign =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> wrong.token)
      |> put_req_header("idempotency-key", "wrong")

    assert json_response(
             post(foreign, ~p"/api/v1/tenants/#{tid}/admin-invitations/#{iid}/accept"),
             404
           )["error"] == "not_found"

    prospect = sign_in("prospect@example.test")

    recipient =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> prospect.token)
      |> put_req_header("idempotency-key", "accept")

    assert json_response(get(recipient, ~p"/api/v1/me/tenant-admin-invitations"), 200)[
             "invitations"
           ]
           |> length() == 1

    assert json_response(
             post(recipient, ~p"/api/v1/tenants/#{tid}/admin-invitations/#{iid}/accept"),
             200
           )["status"] == "accepted"

    assert Ep.Repo.get_by!(Ep.Tenancy.Access,
             tenant_id: tid,
             identity_id: prospect.principal.identity_id
           ).role == "tenant_admin"
  end
end
