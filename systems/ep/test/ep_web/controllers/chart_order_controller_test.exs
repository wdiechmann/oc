defmodule EpWeb.ChartOrderControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, Setup, SetupProjector}

  test "backend-authenticated full order review, atomic acceptance and private completion receipt",
       %{conn: conn} do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Order API"}, "tenant")

    tid = t["tenant_id"]

    {:ok, book} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "Order",
          "code" => "ORDER",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = book["book_id"]

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
        "role"
      )

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "init"
      )

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "account_create",
        %{
          "kind" => "posting",
          "number" => "0010",
          "name" => "Bank",
          "position" => 10,
          "expected_version" => 2
        },
        "bank"
      )

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "account_create",
        %{"kind" => "header", "name" => "Header", "position" => 20, "expected_version" => 3},
        "header"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    path = "/api/v1/tenants/#{tid}/finance/books/#{bid}/chart-order"
    conn = put_req_header(conn, "authorization", "Bearer " <> owner.token)

    assert json_response(get(delete_req_header(conn, "x-ep-backend-token"), path), 401)["error"] ==
             "backend_authentication_required"

    view = json_response(get(conn, path), 200)
    ids = view["rows"] |> Enum.map(& &1["id"]) |> Enum.reverse()

    preview =
      json_response(
        post(conn, path <> "/reviews", %{
          "ordered_ids" => ids,
          "expected_version" => view["source_version"]
        }),
        200
      )

    review_path = path <> "/reviews/" <> preview["review_id"]
    assert json_response(get(conn, review_path), 200)["plan"]["changed_count"] == 2
    attrs = Map.take(preview, ~w(digest expected_version))

    accepted =
      json_response(
        post(put_req_header(conn, "idempotency-key", "order"), review_path <> "/accept", attrs),
        200
      )

    assert accepted["stream_version"] == 6

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceChartOrder:accept",
          "idempotency_key" => "order"
        }),
        200
      )

    assert receipt["status"] == "accepted"
    assert receipt["result"]["event_ids"] == accepted["event_ids"]
    assert json_response(get(conn, path), 409)["error"] == "view_pending"
    {:ok, _} = SetupProjector.deliver(tid)
    updated = get(conn, path)
    assert get_resp_header(updated, "cache-control") == ["no-store"]
    assert Enum.map(json_response(updated, 200)["rows"], & &1["id"]) == ids
  end
end
