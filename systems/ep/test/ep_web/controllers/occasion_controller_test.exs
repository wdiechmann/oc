defmodule EpWeb.OccasionControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  test "scoped HTTP creation ignores authority fields and supports pending/ready/list/retry", %{
    conn: conn
  } do
    s = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(s.principal, %{"name" => "SL"}, "tenant")
    id = t["tenant_id"]

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> s.token)
      |> put_req_header("idempotency-key", "occasion")

    params = %{
      "name" => "SL2030",
      "slug" => "sl2030",
      "expires_at" => "2031-01-01T00:00:00Z",
      "assign_self_as_admin" => true,
      "status" => "active",
      "recruitment_state" => "open",
      "creator_identity_id" => Ecto.UUID.generate()
    }

    result = json_response(post(conn, ~p"/api/v1/tenants/#{id}/occasions", params), 201)
    oid = result["occasion_id"]

    assert json_response(get(conn, ~p"/api/v1/tenants/#{id}/occasions/#{oid}"), 202)["status"] ==
             "pending"

    Oban.drain_queue(queue: :projections)
    body = json_response(get(conn, ~p"/api/v1/tenants/#{id}/occasions/#{oid}"), 200)
    assert body["lifecycle"] == "draft" && body["recruitment_state"] == "closed"

    assert length(json_response(get(conn, ~p"/api/v1/tenants/#{id}/occasions"), 200)["occasions"]) ==
             1

    assert json_response(post(conn, ~p"/api/v1/tenants/#{id}/occasions", params), 200)["replayed"]

    assert json_response(
             post(conn, ~p"/api/v1/tenants/#{id}/occasions", Map.put(params, "name", "Changed")),
             409
           )["error"] == "idempotency_conflict"

    other = sign_in()

    foreign =
      Phoenix.ConnTest.build_conn() |> put_req_header("authorization", "Bearer " <> other.token)

    assert json_response(get(foreign, ~p"/api/v1/tenants/#{id}/occasions/#{oid}"), 404)["error"] ==
             "not_found"

    assert json_response(
             get(conn, ~p"/api/v1/tenants/#{Ecto.UUID.generate()}/occasions/#{oid}"),
             404
           )["error"] == "not_found"
  end
end
