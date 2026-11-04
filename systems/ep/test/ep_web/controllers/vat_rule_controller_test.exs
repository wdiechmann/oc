defmodule EpWeb.VatRuleControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, Setup, SetupProjector, CatalogueEntry}

  test "scoped rule acceptance, quote, receipt and projection over HTTP", %{conn: conn} do
    actor = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(actor.principal, %{"name" => "VAT API"}, "tenant")

    tid = t["tenant_id"]

    {:ok, b} =
      Books.create(
        actor.principal,
        tid,
        %{
          "name" => "VAT",
          "code" => "VAT",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = b["book_id"]

    {:ok, _} =
      Setup.command(
        actor.principal,
        tid,
        bid,
        "steward",
        %{
          "identity_id" => actor.principal.identity_id,
          "active" => true,
          "expected_version" => 0
        },
        "grant"
      )

    {:ok, _} =
      Setup.command(
        actor.principal,
        tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "init"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    entry = Ep.Repo.get_by!(CatalogueEntry, book_id: bid, kind: "vat", code: "input")
    path = "/api/v1/tenants/#{tid}/finance/books/#{bid}/vat-rules"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> actor.token)
      |> put_req_header("idempotency-key", "rule")

    assert json_response(get(delete_req_header(conn, "x-ep-backend-token"), path), 401)["error"] ==
             "backend_authentication_required"

    attrs = %{
      "expected_version" => 2,
      "vat_entry_id" => entry.id,
      "valid_from" => "2026-01-01",
      "valid_until" => nil,
      "direction" => "input",
      "rate_bps" => 2500,
      "deductible_bps" => 10000,
      "mappings" => [%{"box" => "Input", "component" => "deductible_vat", "sign" => 1}]
    }

    accepted = json_response(post(conn, path, attrs), 200)
    assert json_response(post(conn, path, attrs), 200)["replayed"]
    assert json_response(get(conn, path), 200)["status"] == "pending"
    {:ok, _} = SetupProjector.deliver(tid)
    view = get(conn, path)
    assert get_resp_header(view, "cache-control") == ["no-store"]
    rule = hd(json_response(view, 200)["vat_rules"])
    assert rule["id"] == hd(accepted["event_ids"])
    assert length(rule["history"]) == 1

    quote =
      json_response(
        get(conn, path <> "/quote", %{
          "vat_entry_id" => entry.id,
          "date" => "2026-06-01",
          "net_minor" => "10000"
        }),
        200
      )

    assert quote["amounts"]["vat"] == 2500
    assert quote["reporting"] == %{"Input" => 2500}
    assert length(json_response(get(conn, path), 200)["presets"]) == 16

    assert json_response(
             get(conn, path <> "/quote", %{
               "vat_entry_id" => entry.id,
               "date" => "2026-06-01",
               "net_minor" => "10000",
               "assessed_vat_minor" => "bad"
             }),
             422
           )["error"] == "invalid_amount"

    receipt =
      json_response(
        get(conn, "/api/v1/me/commands", %{
          "command_type" => "FinanceSetup:vat_rule_create",
          "idempotency_key" => "rule"
        }),
        200
      )

    assert receipt["status"] == "accepted"

    revision =
      attrs
      |> Map.merge(%{"expected_version" => 3, "expected_rule_version" => 3, "active" => false})
      |> Map.delete("rule_id")

    assert json_response(
             patch(
               put_req_header(conn, "idempotency-key", "deactivate"),
               path <> "/" <> rule["id"],
               revision
             ),
             200
           )["stream_version"] == 4

    assert json_response(
             get(conn, path <> "/quote", %{
               "vat_entry_id" => entry.id,
               "date" => "2026-06-01",
               "net_minor" => "10000"
             }),
             422
           )["error"] == "vat_rule_missing"
  end
end
