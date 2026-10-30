defmodule EpWeb.PeriodControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, PeriodProjector, Setup}

  test "period API enforces lifecycle, separate reopening authority and private receipt recovery",
       %{conn: conn} do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Periods API"}, "tenant")

    tid = t["tenant_id"]

    {:ok, b} =
      Books.create(
        owner.principal,
        tid,
        %{
          "code" => "API",
          "name" => "API",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = b["book_id"]
    root = "/api/v1/tenants/#{tid}/finance/books/#{bid}"
    path = root <> "/periods"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "create")

    assert json_response(get(delete_req_header(conn, "x-ep-backend-token"), path), 401)["error"] ==
             "backend_authentication_required"

    assert json_response(get(conn, path), 200)["permissions"]["configure"] == false

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "steward",
        %{
          "identity_id" => owner.principal.identity_id,
          "active" => true,
          "expected_version" => 0
        },
        "steward"
      )

    attrs = %{
      "name" => "January",
      "start_date" => "2030-01-01",
      "end_date" => "2030-01-31",
      "expected_version" => 0
    }

    result = json_response(post(conn, path, attrs), 200)
    pid = result["period_id"]
    assert json_response(get(conn, path), 200)["status"] == "pending"

    assert json_response(
             get(conn, "/api/v1/me/commands", %{
               "command_type" => "FinancePeriod:create",
               "idempotency_key" => "create"
             }),
             200
           )["result"]["period_id"] == pid

    open = %{"expected_version" => 1, "expected_period_version" => 1}

    assert json_response(
             post(put_req_header(conn, "idempotency-key", "open"), path <> "/#{pid}/open", open),
             200
           )["stream_version"] == 2

    assert json_response(
             post(put_req_header(conn, "idempotency-key", "close"), path <> "/#{pid}/close", %{
               open
               | "expected_version" => 2,
                 "expected_period_version" => 2
             }),
             200
           )["stream_version"] == 3

    reopen = %{
      "expected_version" => 3,
      "expected_period_version" => 3,
      "reason" => "Approved correction"
    }

    assert json_response(
             post(
               put_req_header(conn, "idempotency-key", "reopen"),
               path <> "/#{pid}/reopen",
               reopen
             ),
             404
           )["error"] == "not_found"

    grant = %{
      "identity_id" => owner.principal.identity_id,
      "allow" => true,
      "expected_version" => 1
    }

    assert json_response(
             post(
               put_req_header(conn, "idempotency-key", "grant-reopen"),
               root <> "/setup/reopening-authority",
               grant
             ),
             200
           )["stream_version"] == 2

    assert json_response(
             post(
               put_req_header(conn, "idempotency-key", "reopen"),
               path <> "/#{pid}/reopen",
               reopen
             ),
             200
           )["stream_version"] == 4

    {:ok, _} = PeriodProjector.deliver(tid)
    [period] = json_response(get(conn, path), 200)["periods"]
    assert period["status"] == "open"
    assert List.last(period["history"])["application_id"] == "test-backend"
    stranger = sign_in()

    assert json_response(
             get(put_req_header(conn, "authorization", "Bearer " <> stranger.token), path),
             404
           )["error"] == "not_found"
  end
end
