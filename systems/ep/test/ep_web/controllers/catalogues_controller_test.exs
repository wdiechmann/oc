defmodule EpWeb.CataloguesControllerTest do
  use EpWeb.ConnCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, Setup, SetupProjector}

  test "catalogue API replaces fixed options with scoped entries/history and private receipts", %{
    conn: conn
  } do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Catalogue API"}, "tenant")

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
    root = "/api/v1/tenants/#{tid}/finance/books/#{bid}/setup"
    path = root <> "/catalogues"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "initialize")

    assert json_response(get(delete_req_header(conn, "x-ep-backend-token"), path), 401)["error"] ==
             "backend_authentication_required"

    assert json_response(get(conn, path), 200)["catalogues_initialized"] == false

    assert json_response(post(conn, path <> "/initialize", %{"expected_version" => 0}), 404)[
             "error"
           ] == "not_found"

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

    assert json_response(post(conn, path <> "/initialize", %{"expected_version" => 1}), 200)[
             "stream_version"
           ] == 2

    created =
      json_response(
        post(put_req_header(conn, "idempotency-key", "entry"), path, %{
          "kind" => "vat",
          "code" => "LOCAL",
          "name" => "Local VAT label",
          "expected_version" => 2
        }),
        200
      )

    id = created["entry_id"]
    assert id == hd(created["event_ids"])

    assert json_response(
             get(conn, "/api/v1/me/commands", %{
               "command_type" => "FinanceSetup:catalogue_create",
               "idempotency_key" => "entry"
             }),
             200
           )["result"]["entry_id"] == id

    assert json_response(get(conn, path), 200)["status"] == "pending"
    {:ok, _} = SetupProjector.deliver(tid)
    catalogue = json_response(get(conn, path), 200)
    row = Enum.find(catalogue["catalogue_entries"], &(&1["id"] == id))
    assert row["name"] == "Local VAT label"
    assert hd(row["history"])["application_id"] == "test-backend"

    assert Enum.any?(
             json_response(get(conn, root <> "/accounts"), 200)["options"]["vat_codes"],
             &(&1["id"] == id)
           )

    updated = %{
      "code" => "LOCAL2",
      "name" => "Renamed",
      "active" => false,
      "expected_version" => 3,
      "expected_entry_version" => 3
    }

    assert json_response(
             patch(put_req_header(conn, "idempotency-key", "revise"), path <> "/" <> id, updated),
             200
           )["entry_id"] == id

    stranger = sign_in()

    assert json_response(
             get(put_req_header(conn, "authorization", "Bearer " <> stranger.token), path),
             404
           )["error"] == "not_found"
  end
end
