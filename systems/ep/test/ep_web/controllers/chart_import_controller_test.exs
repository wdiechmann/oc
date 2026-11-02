defmodule EpWeb.ChartImportControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, Setup, SetupProjector}

  test "backend-scoped upload, mapping, acceptance, export and private receipt", %{conn: conn} do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "CSV API"}, "tenant")

    tid = t["tenant_id"]

    {:ok, book} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "CSV",
          "code" => "CSV",
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

    {:ok, _} = SetupProjector.deliver(tid)
    path = "/api/v1/tenants/#{tid}/finance/books/#{bid}"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "csv")

    assert json_response(
             get(delete_req_header(conn, "x-ep-backend-token"), path <> "/chart-imports"),
             401
           )["error"] == "backend_authentication_required"

    assert json_response(get(conn, path <> "/chart-imports"), 200)["max_rows"] == 500

    upload =
      json_response(
        post(conn, path <> "/chart-imports", %{
          "headers" => ~w(type number name position),
          "records" => [["posting", "0010", "Bank", "100"]]
        }),
        200
      )

    review_path = path <> "/chart-imports/" <> upload["import_id"]
    assert json_response(get(conn, review_path), 200)["plan"] == nil

    preview =
      json_response(post(conn, review_path <> "/preview", %{"mapping" => upload["mapping"]}), 200)

    assert preview["plan"]["valid"]
    attrs = Map.take(preview, ~w(digest expected_version))
    result = json_response(post(conn, review_path <> "/accept", attrs), 200)
    assert result["stream_version"] == 3
    assert json_response(post(conn, review_path <> "/accept", attrs), 200)["replayed"]

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceChartImport:accept",
          "idempotency_key" => "csv"
        }),
        200
      )

    assert receipt["status"] == "accepted"
    assert receipt["result"]["event_ids"] == result["event_ids"]
    assert json_response(get(conn, path <> "/chart-export"), 409)["error"] == "view_pending"
    {:ok, _} = SetupProjector.deliver(tid)
    export_conn = get(conn, path <> "/chart-export")
    assert get_resp_header(export_conn, "cache-control") == ["no-store"]
    exported = json_response(export_conn, 200)
    assert exported["row_count"] == 1
    assert Enum.at(hd(exported["rows"]), 7) == "0010"

    assert json_response(get(conn, path <> "/chart-export", %{"source_version" => "2"}), 409)[
             "error"
           ] == "chart_changed"
  end
end
