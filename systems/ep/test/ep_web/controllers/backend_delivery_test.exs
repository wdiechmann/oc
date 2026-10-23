defmodule EpWeb.BackendDeliveryTest do
  use EpWeb.ConnCase, async: true
  import Ecto.Query
  alias Ep.Repo

  defp backend,
    do: build_conn() |> put_req_header("x-ep-backend-token", String.duplicate("b", 48))

  defp login(email) do
    issued = post(backend(), ~p"/api/v1/auth/magic-links", %{"email" => email})
    assert get_resp_header(issued, "cache-control") == ["no-store"]
    delivery = json_response(issued, 202)["delivery"]
    assert delivery["email"] == email

    token =
      json_response(
        post(backend(), ~p"/api/v1/auth/magic-links/verify", %{"token" => delivery["token"]}),
        200
      )["token"]

    backend() |> put_req_header("authorization", "Bearer " <> token)
  end

  test "issuance and redemption are backend-only and challenges are backend-bound" do
    assert json_response(
             post(build_conn(), ~p"/api/v1/auth/magic-links", %{"email" => "no@example.test"}),
             401
           )["error"] == "backend_authentication_required"

    assert Repo.aggregate(Ep.Auth.MagicLink, :count) == 0

    assert {:ok, %{delivery: %{token: token}}} =
             Ep.Auth.request_magic_link("bound@example.test", "another-backend")

    assert json_response(
             post(backend(), ~p"/api/v1/auth/magic-links/verify", %{
               "token" => token,
               "backend_id" => "another-backend"
             }),
             401
           )["error"] == "invalid_token"

    assert {:ok, _} = Ep.Auth.verify_magic_link(token, "another-backend")
  end

  test "all seven admin flows use API delivery and preserve grants on subsequent sign-ins" do
    # 1. First tenant-admin signup/sign-in.
    owner = login("owner-seven@example.test") |> put_req_header("idempotency-key", "tenant")

    tid =
      json_response(post(owner, ~p"/api/v1/tenants", %{"name" => "Seven flows"}), 201)[
        "tenant_id"
      ]

    # 2. Invite tenant admin, including safe retrieval after uncertain client delivery.
    owner = put_req_header(owner, "idempotency-key", "invite-tenant")

    first =
      json_response(
        post(owner, ~p"/api/v1/tenants/#{tid}/admin-invitations", %{
          "email" => "tenant-seven@example.test"
        }),
        201
      )

    assert first["delivery"]["email"] == "tenant-seven@example.test"

    assert json_response(
             post(owner, ~p"/api/v1/tenants/#{tid}/admin-invitations", %{
               "email" => "tenant-seven@example.test"
             }),
             200
           )["delivery"] == first["delivery"]

    # 3. Verified recipient accepts tenant invitation.
    tenant_admin =
      login("tenant-seven@example.test") |> put_req_header("idempotency-key", "accept-tenant")

    iid = first["invitation_id"]

    assert json_response(
             post(tenant_admin, ~p"/api/v1/tenants/#{tid}/admin-invitations/#{iid}/accept"),
             200
           )["status"] == "accepted"

    # 4. Subsequent tenant-admin sign-in discovers the same tenant.
    tenant_admin =
      login("tenant-seven@example.test") |> put_req_header("idempotency-key", "occasion")

    Oban.drain_queue(queue: :projections)

    assert [%{"tenant_id" => ^tid}] =
             json_response(get(tenant_admin, ~p"/api/v1/me/workspaces"), 200)["tenants"]

    # 5. Invite an admin for an exact occasion, never a tenant grant.
    oid =
      json_response(
        post(tenant_admin, ~p"/api/v1/tenants/#{tid}/occasions", %{
          "name" => "SL2030",
          "slug" => "sl2030",
          "expires_at" => "2032-01-01T00:00:00Z"
        }),
        201
      )["occasion_id"]

    tenant_admin = put_req_header(tenant_admin, "idempotency-key", "invite-occasion")

    invited =
      json_response(
        post(tenant_admin, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations", %{
          "email" => "occasion-seven@example.test"
        }),
        201
      )

    assert invited["delivery"]["occasion_id"] == oid
    assert invited["delivery"]["role"] == "occasion_admin"
    # 6. Verified recipient accepts occasion invitation.
    occasion_admin =
      login("occasion-seven@example.test") |> put_req_header("idempotency-key", "accept-occasion")

    iid = invited["invitation_id"]

    assert json_response(
             post(
               occasion_admin,
               ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/admin-invitations/#{iid}/accept"
             ),
             200
           )["status"] == "accepted"

    # 7. Subsequent sign-in restores only authorized navigation, without new grants.
    occasion_admin = login("occasion-seven@example.test")
    Oban.drain_queue(queue: :projections)
    workspaces = json_response(get(occasion_admin, ~p"/api/v1/me/workspaces"), 200)
    assert workspaces["tenants"] == []
    assert [%{"occasion_id" => ^oid}] = workspaces["occasions"]
    assert Repo.aggregate(Ep.Tenancy.Access, :count) == 2
    assert Repo.aggregate(Ep.Occasions.Admin, :count) == 1
    assert Repo.aggregate(from(j in Oban.Job, where: j.queue == "default"), :count) == 0
    receipts = Repo.all(Ep.Events.CommandReceipt)
    assert Enum.all?(receipts, &(not Map.has_key?(&1.result, "delivery")))

    assert Enum.all?(
             Repo.all(Ep.Events.Details),
             &(not Map.has_key?(&1.payload, "email") && not Map.has_key?(&1.payload, "token"))
           )
  end
end
