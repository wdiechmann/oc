defmodule EpWeb.HealthControllerTest do
  use EpWeb.ConnCase, async: true

  test "liveness returns JSON", %{conn: conn} do
    conn = get(conn, ~p"/health/live")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "readiness verifies migrated persistence and the queue supervisor", %{conn: conn} do
    conn = get(conn, ~p"/health/ready")
    assert json_response(conn, 200) == %{"status" => "ready"}
  end
end
