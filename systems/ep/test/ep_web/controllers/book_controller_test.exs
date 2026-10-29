defmodule EpWeb.BookControllerTest do
  use EpWeb.ConnCase, async: true
  import Ecto.Query
  import Ep.Support.AuthHelpers
  alias Ep.{Repo, Finance.Books, Finance.BookProjector}

  defp attrs(code),
    do: %{
      "name" => code,
      "code" => code,
      "base_currency" => "DKK",
      "accounting_authority" => "ep",
      "timezone" => "Europe/Copenhagen",
      "fiscal_year_start_month" => 1
    }

  test "book API returns pending/ready views and current-authority revision conflicts", %{
    conn: conn
  } do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "API books"}, "tenant")

    root = "/api/v1/tenants/#{t["tenant_id"]}/finance/books"

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "book")

    attrs = attrs("SL2030")
    result = json_response(post(conn, root, attrs), 200)
    detail = json_response(get(conn, root <> "/" <> result["book_id"]), 200)
    assert detail["status"] == "pending"
    assert detail["book"] == nil
    {:ok, _} = BookProjector.deliver(t["tenant_id"])
    assert json_response(get(conn, root), 200)["tenant_name"] == "API books"
    path = root <> "/" <> result["book_id"]

    assert json_response(patch(conn, path, %{"expected_version" => 1, "name" => "Renamed"}), 200)[
             "stream_version"
           ] == 2

    stale =
      conn
      |> put_req_header("idempotency-key", "stale")
      |> patch(path, %{"expected_version" => 1, "name" => "Lost update"})

    assert json_response(stale, 409)["error"] == "version_conflict"

    Repo.update_all(from(a in Ep.Tenancy.Access, where: a.tenant_id == ^t["tenant_id"]),
      set: [status: "revoked"]
    )

    assert json_response(get(conn, path), 404)["error"] == "not_found"
  end

  test "invalid configuration and extra scope fields cannot create partial books", %{conn: conn} do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Validation"}, "tenant")

    api =
      conn
      |> put_req_header("authorization", "Bearer " <> owner.token)
      |> put_req_header("idempotency-key", "invalid")

    root = "/api/v1/tenants/#{t["tenant_id"]}/finance/books"

    for changed <- [
          %{"base_currency" => "XYZ"},
          %{"fiscal_year_start_month" => 13},
          %{"occasion_id" => Ecto.UUID.generate()}
        ] do
      response = post(api, root, Map.merge(attrs("INVALID"), changed))
      assert json_response(response, 422)["error"] == "invalid_book"
    end

    assert Repo.aggregate(Ep.Finance.Book, :count) == 0
    assert {:error, :not_found} = Books.list(owner.principal, Ecto.UUID.generate())
  end
end
