defmodule EpWeb.FinanceSetupControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, SetupProjector}

  test "explicit grants, account commands, private receipts and live revocation over HTTP", %{
    conn: conn
  } do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "API finance"}, "tenant")

    tid = t["tenant_id"]

    {:ok, b} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "API",
          "code" => "API",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    path = "/api/v1/tenants/#{tid}/finance/books/#{b["book_id"]}/setup"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "grant")

    missing_backend = delete_req_header(conn, "x-ep-backend-token")

    assert json_response(get(missing_backend, path), 401)["error"] ==
             "backend_authentication_required"

    assert json_response(get(conn, path), 200)["permissions"] == %{
             "assign_stewards" => true,
             "configure" => false
           }

    assert json_response(
             post(conn, path <> "/accounts", %{
               "number" => "0010",
               "name" => "Bank",
               "kind" => "posting",
               "expected_version" => 0
             }),
             404
           )["error"] == "not_found"

    grant = %{
      "identity_id" => owner.principal.identity_id,
      "active" => true,
      "expected_version" => 0
    }

    assert json_response(post(conn, path <> "/stewards", grant), 200)["stream_version"] == 1
    account_conn = put_req_header(conn, "idempotency-key", "account")
    attrs = %{"number" => "0010", "name" => "Bank", "kind" => "posting", "expected_version" => 1}
    account = json_response(post(account_conn, path <> "/accounts", attrs), 200)
    assert account["stream_version"] == 2

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceSetup:account_create",
          "idempotency_key" => "account"
        }),
        200
      )

    assert receipt["status"] == "accepted"
    assert receipt["result"]["event_ids"] == account["event_ids"]
    assert json_response(get(conn, path), 200)["status"] == "pending"
    {:ok, _} = SetupProjector.deliver(tid)
    row = json_response(get(conn, path), 200)["accounts"] |> hd()
    assert row["id"] == hd(account["event_ids"])
    assert row["application_id"] == "test-backend"

    chart =
      json_response(get(conn, path <> "/accounts", %{"page" => "1", "per_page" => "1"}), 200)

    assert chart["pagination"] == %{
             "page" => 1,
             "per_page" => 1,
             "total_entries" => 1,
             "total_pages" => 1
           }

    assert chart["accounts"] |> hd() |> Map.get("number") == "0010"
    assert chart["options"]["vat_codes"] == ["none", "input", "output"]

    revised =
      Map.merge(attrs, %{
        "expected_version" => 2,
        "expected_account_version" => 2,
        "active" => true,
        "name" => "Cash"
      })

    assert json_response(
             patch(
               put_req_header(conn, "idempotency-key", "revise"),
               path <> "/accounts/" <> row["id"],
               revised
             ),
             200
           )["stream_version"] == 3

    revoke = %{grant | "active" => false, "expected_version" => 3}

    assert json_response(
             post(put_req_header(conn, "idempotency-key", "revoke"), path <> "/stewards", revoke),
             200
           )["stream_version"] == 4

    assert json_response(post(account_conn, path <> "/accounts", attrs), 404)["error"] ==
             "not_found"

    stranger = sign_in()
    foreign = put_req_header(conn, "authorization", "Bearer " <> stranger.token)
    assert json_response(get(foreign, path), 404)["error"] == "not_found"

    assert json_response(
             get(foreign, "/api/v1/me/commands", %{
               "command_type" => "FinanceSetup:account_create",
               "idempotency_key" => "account"
             }),
             200
           )["status"] == "unknown"
  end
end
