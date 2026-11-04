defmodule EpWeb.JournalControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Books,
    ChartImports,
    JournalProjector,
    Periods,
    PeriodProjector,
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

    {:ok, p} =
      Periods.command(
        owner.principal,
        tid,
        bid,
        "create",
        %{
          "name" => "2026",
          "start_date" => "2026-01-01",
          "end_date" => "2026-12-31",
          "expected_version" => 0
        },
        "period"
      )

    {:ok, _} =
      Periods.command(
        owner.principal,
        tid,
        bid,
        "open",
        %{"period_id" => p["period_id"], "expected_version" => 1, "expected_period_version" => 1},
        "open"
      )

    {:ok, _} = PeriodProjector.deliver(tid)

    %{
      actor: owner.principal,
      token: owner.token,
      tid: tid,
      bid: bid,
      csv_review: preview,
      period_id: p["period_id"]
    }
  end

  test "reviewed draft transport is private, revision fenced and never posts", c do
    conn = Plug.Conn.put_req_header(c.conn, "authorization", "Bearer " <> c.token)
    path = "/api/v1/tenants/#{c.tid}/finance/books/#{c.bid}/journals"

    assert json_response(get(Plug.Conn.delete_req_header(conn, "x-ep-backend-token"), path), 401)[
             "error"
           ] == "backend_authentication_required"

    data = json_response(get(conn, path), 200)
    [a, b] = data["accounts"]

    line = fn id, d, cr ->
      %{
        "id" => nil,
        "account_id" => id,
        "reference" => "",
        "debit_minor" => d,
        "credit_minor" => cr,
        "vat_entry_id" => nil,
        "net_minor" => nil,
        "assessed_vat_minor" => nil
      }
    end

    body = %{
      "draft_id" => nil,
      "expected_draft_version" => nil,
      "expected_version" => 0,
      "contexts" => data["contexts"],
      "data" => %{
        "name" => "HTTP draft",
        "posting_date" => "2026-06-01",
        "reference" => "REF",
        "lines" => [line.(a["id"], 25, 0), line.(b["id"], 0, 25)]
      }
    }

    review = json_response(post(conn, path <> "/reviews", body), 200)
    assert review["plan"]["validation"]["status"] == "prepared"
    pointer = Map.take(review, ~w(review_id digest expected_version))

    accepted =
      json_response(
        post(
          Plug.Conn.put_req_header(conn, "idempotency-key", "draft"),
          path <> "/accept",
          pointer
        ),
        200
      )

    assert accepted["draft_id"]
    {:ok, _} = JournalProjector.deliver(c.tid)
    response = get(conn, path, %{"draft_id" => accepted["draft_id"]})
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert json_response(response, 200)["selected"]["data"]["name"] == "HTTP draft"

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceJournalDraft:save",
          "idempotency_key" => "draft"
        }),
        200
      )

    assert receipt["status"] == "accepted"

    assert json_response(post(conn, path <> "/reviews", %{body | "expected_version" => 99}), 409)[
             "error"
           ] == "version_conflict"

    assert json_response(get(conn, String.replace(path, c.tid, Ecto.UUID.generate())), 404)[
             "error"
           ] == "not_found"
  end
end
