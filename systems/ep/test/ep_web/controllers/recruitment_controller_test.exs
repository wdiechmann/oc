defmodule EpWeb.RecruitmentControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  test "HTTP recruitment publishes minimal policy and intake remains pending", %{conn: conn} do
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
      |> put_req_header("idempotency-key", "open")

    params = %{
      "title" => "Join us",
      "instructions" => "Manual review",
      "privacy_notice_url" => "https://example.test/privacy",
      "confirm_manual_review" => true,
      "lead_vouch_required" => false,
      "admission" => "automatic"
    }

    assert json_response(
             post(admin, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/recruitment/open", params),
             200
           )["recruitment_state"] == "open"

    Oban.drain_queue(queue: :projections)
    public = json_response(get(build_conn(), ~p"/api/v1/recruitment/#{tid}/sl2030"), 200)
    assert public["config"]["lead_vouch_required"]
    refute Map.has_key?(public, "email")
    prospect = sign_in()

    applicant =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> prospect.token)
      |> put_req_header("idempotency-key", "apply")

    submission =
      post(applicant, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/recruitment/applications", %{
        "notice_version" => public["config"]["notice_version"],
        "acknowledge_notice" => true,
        "status" => "accepted"
      })

    assert json_response(submission, 201)["status"] == "pending_review"

    assert json_response(
             get(applicant, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/recruitment/applications"),
             404
           )["error"] == "not_found"

    assert json_response(
             post(admin, ~p"/api/v1/tenants/#{tid}/occasions/#{oid}/recruitment/close", %{
               "reason" => "Done"
             }),
             200
           )["recruitment_state"] == "closed"

    assert json_response(get(build_conn(), ~p"/api/v1/recruitment/#{tid}/sl2030"), 409)["error"] ==
             "recruitment_closed"
  end
end
