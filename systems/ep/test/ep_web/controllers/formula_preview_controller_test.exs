defmodule EpWeb.FormulaPreviewControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, ChartImports, Setup, SetupProjector}

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
          ["header", "", "Header", "20", ""],
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

  test "preview transport requires current scope/backend and returns no-store exact values", c do
    conn = Plug.Conn.put_req_header(c.conn, "authorization", "Bearer " <> c.token)
    path = "/api/v1/tenants/#{c.tid}/finance/books/#{c.bid}/formula-preview"

    assert json_response(get(Plug.Conn.delete_req_header(conn, "x-ep-backend-token"), path), 401)[
             "error"
           ] == "backend_authentication_required"

    response = get(conn, path)
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    chart = json_response(response, 200)
    posting = Enum.find(chart["rows"], &(&1["kind"] == "posting"))

    params = %{
      "expected_version" => chart["source_version"],
      "balances" => %{posting["id"] => -3}
    }

    result = json_response(post(conn, path, params), 200)
    assert hd(result["results"])["amount_minor"] == -6
    assert hd(result["results"])["exact"] == %{"numerator" => "-6", "denominator" => "1"}

    assert json_response(post(conn, path, %{params | "expected_version" => 0}), 409)["error"] ==
             "version_conflict"

    assert json_response(
             post(conn, path, %{params | "balances" => %{posting["id"] => "-3"}}),
             422
           )["error"] == "invalid_balances"

    assert json_response(get(conn, String.replace(path, c.tid, Ecto.UUID.generate())), 404)[
             "error"
           ] == "not_found"
  end
end
