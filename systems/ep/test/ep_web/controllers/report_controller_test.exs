defmodule EpWeb.ReportControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Books,
    ChartImports,
    Setup,
    SetupProjector
  }

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Ordering"}, "tenant")

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
        "grant"
      )

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "initialize"
      )

    {:ok, _} = SetupProjector.deliver(tid)

    {:ok, upload} =
      ChartImports.upload(owner.principal, tid, bid, %{
        "headers" => ~w(type number name position formula),
        "records" => [
          ["posting", "0010", "Bank", "10", ""],
          ["posting", "0020", "Costs", "20", ""],
          ["calculation", "", "Total", "30", "[0010] * 2"]
        ]
      })

    {:ok, preview} =
      ChartImports.preview(owner.principal, tid, bid, upload.import_id, %{
        "mapping" => upload.mapping
      })

    {:ok, _} =
      ChartImports.accept(
        owner.principal,
        tid,
        bid,
        upload.import_id,
        %{"digest" => preview.digest, "expected_version" => preview.expected_version},
        "seed"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    %{actor: owner.principal, token: owner.token, tid: tid, bid: bid, csv_review: preview}
  end

  test "backend-scoped review, acceptance, projection, preview and private receipt", c do
    conn = Plug.Conn.put_req_header(c.conn, "authorization", "Bearer " <> c.token)
    path = "/api/v1/tenants/#{c.tid}/finance/books/#{c.bid}/reports"

    assert json_response(get(Plug.Conn.delete_req_header(conn, "x-ep-backend-token"), path), 401)[
             "error"
           ] == "backend_authentication_required"

    chart = json_response(get(conn, path), 200)
    account = hd(chart["accounts"])

    draft = %{
      "name" => "HTTP report",
      "report_id" => nil,
      "expected_report_version" => nil,
      "expected_version" => chart["latest_version"],
      "active" => true,
      "lines" => [
        %{
          "id" => nil,
          "code" => "BANK",
          "name" => "Bank",
          "kind" => "mapping",
          "position" => 100,
          "account_ids" => [account["id"]],
          "formula" => "",
          "sign" => -1
        }
      ]
    }

    review = json_response(post(conn, path <> "/reviews", draft), 200)
    pointer = Map.take(review, ~w(review_id digest expected_version))

    accepted =
      json_response(
        post(
          Plug.Conn.put_req_header(conn, "idempotency-key", "report"),
          path <> "/accept",
          pointer
        ),
        200
      )

    id = hd(accepted["event_ids"])
    {:ok, _} = SetupProjector.deliver(c.tid)

    response =
      post(conn, path <> "/" <> id <> "/preview", %{
        "report_version" => accepted["stream_version"],
        "balances" => %{account["id"] => 25}
      })

    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert hd(json_response(response, 200)["results"])["amount_minor"] == -25

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceSetup:report_save",
          "idempotency_key" => "report"
        }),
        200
      )

    assert receipt["status"] == "accepted"
  end
end
