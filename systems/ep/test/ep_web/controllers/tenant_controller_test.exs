defmodule EpWeb.TenantControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  test "full authenticated HTTP create, pending view and projected read", %{conn: conn} do
    signed = sign_in()

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> signed.token)
      |> put_req_header("idempotency-key", "http-1")

    accepted =
      post(conn, ~p"/api/v1/tenants", %{
        "name" => "Scout camp",
        "creator_identity_id" => Ecto.UUID.generate()
      })

    body = json_response(accepted, 201)
    id = body["tenant_id"]
    assert length(body["event_ids"]) == 2
    assert Ep.Repo.get!(Ep.Tenancy.Tenant, id).creator_identity_id == signed.principal.identity_id
    assert get_resp_header(accepted, "location") == ["/api/v1/tenants/" <> id]
    assert json_response(get(conn, ~p"/api/v1/tenants/#{id}"), 202)["status"] == "pending"
    Oban.drain_queue(queue: :projections)
    assert json_response(get(conn, ~p"/api/v1/tenants/#{id}"), 200)["name"] == "Scout camp"

    assert json_response(post(conn, ~p"/api/v1/tenants", %{"name" => "Scout camp"}), 200)[
             "replayed"
           ]

    assert json_response(post(conn, ~p"/api/v1/tenants", %{"name" => "Changed"}), 409)["error"] ==
             "idempotency_conflict"
  end

  test "identity headers cannot spoof authentication", %{conn: conn} do
    conn = put_req_header(conn, "x-identity-id", Ecto.UUID.generate())

    assert json_response(post(conn, ~p"/api/v1/tenants", %{"name" => "No"}), 401)["error"] ==
             "unauthenticated"
  end

  test "tenant reads do not reveal another creator's tenant", %{conn: conn} do
    a = sign_in()
    b = sign_in()

    {:ok, %{result: result}} =
      Ep.Tenancy.create_tenant(a.principal, %{"name" => "Hidden"}, "hidden")

    id = result["tenant_id"]
    Oban.drain_queue(queue: :projections)
    conn = put_req_header(conn, "authorization", "Bearer " <> b.token)
    assert json_response(get(conn, ~p"/api/v1/tenants/#{id}"), 404) == %{"error" => "not_found"}
  end

  test "missing idempotency key and invalid name reject with 422", %{conn: conn} do
    signed = sign_in()
    conn = put_req_header(conn, "authorization", "Bearer " <> signed.token)

    assert json_response(post(conn, ~p"/api/v1/tenants", %{"name" => "Name"}), 422)["error"] ==
             "invalid_idempotency_key"

    conn = put_req_header(conn, "idempotency-key", "valid")

    assert json_response(post(conn, ~p"/api/v1/tenants", %{"name" => ""}), 422)["error"] ==
             "invalid_name"
  end
end
