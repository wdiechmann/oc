defmodule EpWeb.AuthControllerTest do
  use EpWeb.ConnCase, async: true

  test "email verification returns a session and cannot be reused", %{conn: conn} do
    assert json_response(
             post(conn, ~p"/api/v1/auth/magic-links", %{"email" => "http@example.test"}),
             202
           )["status"] == "check_your_email"

    assert_receive {:magic_link, _, token}
    response = post(conn, ~p"/api/v1/auth/magic-links/verify", %{"token" => token})
    body = json_response(response, 200)
    assert {:ok, _} = Ep.Auth.authenticate(body["token"])
    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert json_response(
             post(conn, ~p"/api/v1/auth/magic-links/verify", %{"token" => token}),
             401
           )["error"] == "invalid_token"
  end
end
