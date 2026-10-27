defmodule EpWeb.AuthControllerTest do
  use EpWeb.ConnCase, async: true
  import Ecto.Query

  test "email verification returns a session and cannot be reused", %{conn: conn} do
    response =
      json_response(
        post(conn, ~p"/api/v1/auth/magic-links", %{"email" => "http@example.test"}),
        202
      )

    assert response["status"] == "check_your_email"

    token = response["delivery"]["token"]
    response = post(conn, ~p"/api/v1/auth/magic-links/verify", %{"token" => token})
    body = json_response(response, 200)
    assert {:ok, _} = Ep.Auth.authenticate(body["token"])
    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert json_response(
             post(conn, ~p"/api/v1/auth/magic-links/verify", %{"token" => token}),
             401
           )["error"] == "invalid_token"
  end

  test "sign-in-only links reuse an existing identity and never register an unknown email", %{
    conn: conn
  } do
    assert json_response(
             post(conn, "/api/v1/auth/sign-in-links", %{"email" => "unknown@example.test"}),
             202
           )["delivery"] == nil

    assert Ep.Repo.aggregate(Ep.Auth.Identity, :count) == 0
    {:ok, %{delivery: %{token: initial}}} = Ep.Auth.request_magic_link("existing@example.test")
    {:ok, original} = Ep.Auth.verify_magic_link(initial)

    issued =
      json_response(
        post(conn, "/api/v1/auth/sign-in-links", %{"email" => "existing@example.test"}),
        202
      )

    assert issued["delivery"]["token"]
    token = issued["delivery"]["token"]
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(token, "other-backend")

    result =
      json_response(post(conn, "/api/v1/auth/magic-links/verify", %{"token" => token}), 200)

    assert {:ok, principal} = Ep.Auth.authenticate(result["token"])
    assert principal.identity_id == original.principal.identity_id
    assert Ep.Repo.aggregate(Ep.Auth.Identity, :count) == 1
    authenticated = put_req_header(conn, "authorization", "Bearer " <> result["token"])

    assert json_response(delete(authenticated, "/api/v1/auth/session"), 200)["status"] ==
             "signed_out"

    assert {:error, :unauthenticated} = Ep.Auth.authenticate(result["token"])
    assert {:ok, _} = Ep.Auth.authenticate(original.token)
  end

  test "sign-in-only link cannot follow a reassigned email to a different identity", %{conn: conn} do
    {:ok, %{delivery: %{token: initial}}} = Ep.Auth.request_magic_link("changed@example.test")
    {:ok, original} = Ep.Auth.verify_magic_link(initial)

    link =
      json_response(
        post(conn, "/api/v1/auth/sign-in-links", %{"email" => "changed@example.test"}),
        202
      )["delivery"]["token"]

    Ep.Repo.update_all(
      from(i in Ep.Auth.Identity, where: i.id == ^original.principal.identity_id),
      set: [email: "replacement@example.test"]
    )

    assert json_response(post(conn, "/api/v1/auth/magic-links/verify", %{"token" => link}), 401)[
             "error"
           ] == "invalid_token"

    assert Ep.Repo.aggregate(Ep.Auth.Identity, :count) == 1
  end
end
