defmodule EpWeb.MonitoringControllerTest do
  use EpWeb.ConnCase, async: true
  alias Ep.{Auth, Repo}
  alias Ep.Monitoring.Source

  setup do
    {:ok, %{delivery: %{token: token}}} = Auth.request_magic_link("monitor@example.test")
    {:ok, auth} = Auth.verify_magic_link(token)

    {:ok, %{result: tenant}} =
      Ep.Tenancy.create_tenant(auth.principal, %{"name" => "Monitor"}, "tenant")

    tid = tenant["tenant_id"]

    source =
      Repo.insert!(%Source{
        backend_id: "test-backend",
        identity_id: auth.principal.identity_id,
        tenant_id: tid,
        status: "active"
      })

    conn =
      build_conn()
      |> put_req_header("x-ep-backend-token", String.duplicate("b", 48))
      |> put_req_header("authorization", "Bearer " <> auth.token)

    %{api: conn, source: source, tid: tid, auth: auth, tenant: tenant}
  end

  defp observation(source, code \\ "application.exception") do
    %{
      "source_id" => source.id,
      "source_observation_id" => Ecto.UUID.generate(),
      "code" => code,
      "correlation_id" => Ecto.UUID.generate(),
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  test "backend-only ingestion persists safe facts, deduplicates and projects an authorized list",
       c do
    payload = observation(c.source)

    assert json_response(post(build_conn(), "/api/v1/monitoring/observations", payload), 401)[
             "error"
           ] == "backend_authentication_required"

    first = json_response(post(c.api, "/api/v1/monitoring/observations", payload), 201)
    assert first["issue_id"]
    assert first["event_ids"] != []
    assert json_response(post(c.api, "/api/v1/monitoring/observations", payload), 200)["replayed"]

    assert json_response(
             post(
               c.api,
               "/api/v1/monitoring/observations",
               Map.put(payload, "code", "request.conflict")
             ),
             409
           )["error"] == "idempotency_conflict"

    Oban.drain_queue(queue: :monitoring)
    list = json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues"), 200)
    assert [%{"id" => id, "data" => %{"count" => 1, "severity" => "error"}}] = list["items"]
    assert id == first["issue_id"]

    assert json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}"), 200)[
             "issue"
           ]["id"] == id
  end

  test "rejects arbitrary payload/authority and revoked sources", c do
    p = observation(c.source)

    for extra <- [
          %{"message" => "secret@example.test"},
          %{"tenant_id" => c.tid},
          %{"token" => "secret"}
        ] do
      assert json_response(
               post(c.api, "/api/v1/monitoring/observations", Map.merge(p, extra)),
               422
             )["error"] == "invalid_observation"
    end

    Repo.update!(Ecto.Changeset.change(c.source, status: "revoked"))

    assert json_response(post(c.api, "/api/v1/monitoring/observations", p), 404)["error"] ==
             "not_found"
  end

  test "issue actions enforce versions, are idempotent and survive projection delay", c do
    result =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    id = result["issue_id"]
    action = %{"action" => "acknowledge", "expected_version" => result["stream_version"]}
    api = put_req_header(c.api, "idempotency-key", "ack")

    assert json_response(
             post(api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}/actions", action),
             200
           )["stream_version"] > result["stream_version"]

    assert json_response(
             post(api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}/actions", action),
             200
           )["replayed"]

    assert json_response(
             post(
               put_req_header(api, "idempotency-key", "stale"),
               "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}/actions",
               action
             ),
             409
           )["error"] == "version_conflict"

    Oban.drain_queue(queue: :monitoring)

    assert json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}"), 200)[
             "issue"
           ]["data"]["state"] == "acknowledged"
  end

  test "command reconciliation is private and distinguishes unknown from accepted", c do
    result = json_response(get(c.api, "/api/v1/me/commands/#{c.tenant["command_id"]}"), 200)
    assert result["status"] == "accepted"
    assert result["result"]["tenant_id"] == c.tid

    assert json_response(get(c.api, "/api/v1/me/commands/#{Ecto.UUID.generate()}"), 200)["status"] ==
             "unknown"
  end

  test "other identities cannot reconcile commands or read monitoring without current authority",
       c do
    {:ok, %{delivery: %{token: token}}} = Auth.request_magic_link("stranger-monitor@example.test")
    {:ok, stranger} = Auth.verify_magic_link(token)
    api = build_conn() |> put_req_header("authorization", "Bearer " <> stranger.token)

    assert json_response(get(api, "/api/v1/tenants/#{c.tid}/monitoring/issues"), 404)["error"] ==
             "not_found"

    assert json_response(get(api, "/api/v1/me/commands/#{c.tenant["command_id"]}"), 200)["status"] ==
             "unknown"

    query = URI.encode_query(%{"command_type" => "CreateTenant", "idempotency_key" => "tenant"})

    assert json_response(get(c.api, "/api/v1/me/commands?" <> query), 200)["command_id"] ==
             c.tenant["command_id"]
  end

  test "occasion admins cannot read tenant-wide or sibling monitoring", c do
    {:ok, %{result: occasion}} =
      Ep.Occasions.create(
        c.auth.principal,
        c.tid,
        %{"name" => "Scope", "slug" => "scope", "expires_at" => "2032-01-01T00:00:00Z"},
        "occasion"
      )

    oid = occasion["occasion_id"]
    {:ok, %{delivery: %{token: token}}} = Auth.request_magic_link("occasion-monitor@example.test")
    {:ok, admin} = Auth.verify_magic_link(token)

    grant =
      Repo.insert!(%Ep.Occasions.Admin{
        tenant_id: c.tid,
        occasion_id: oid,
        identity_id: admin.principal.identity_id
      })

    scoped =
      Repo.insert!(%Source{
        backend_id: "test-backend",
        identity_id: c.auth.principal.identity_id,
        tenant_id: c.tid,
        occasion_id: oid,
        status: "active"
      })

    own = json_response(post(c.api, "/api/v1/monitoring/observations", observation(scoped)), 201)

    foreign =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    Oban.drain_queue(queue: :monitoring)
    api = build_conn() |> put_req_header("authorization", "Bearer " <> admin.token)

    assert json_response(get(api, "/api/v1/tenants/#{c.tid}/monitoring/issues"), 404)["error"] ==
             "not_found"

    assert [%{"id" => id}] =
             json_response(
               get(api, "/api/v1/tenants/#{c.tid}/monitoring/issues?occasion_id=#{oid}"),
               200
             )["items"]

    assert id == own["issue_id"]

    assert json_response(
             get(api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{foreign["issue_id"]}"),
             404
           )["error"] == "not_found"

    Repo.update!(Ecto.Changeset.change(grant, status: "revoked"))

    assert json_response(get(api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}"), 404)[
             "error"
           ] == "not_found"
  end

  test "stopped monitoring blocks reads and processing while ingestion remains durable", c do
    result =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    control = Repo.get_by!(Ep.Projections.Control, tenant_id: c.tid, name: "monitoring")
    control = Repo.update!(Ecto.Changeset.change(control, state: "stopped"))
    assert {:error, :view_stopped} = Ep.Monitoring.Projector.deliver(result["issue_id"])
    assert Repo.aggregate(Ep.Monitoring.Pending, :count) == 2

    assert json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues"), 503)["error"] ==
             "view_stopped"

    Repo.update!(Ecto.Changeset.change(control, state: "running"))
    assert {:ok, 2} = Ep.Monitoring.Projector.deliver(result["issue_id"])
    assert {:ok, 0} = Ep.Monitoring.Projector.deliver(result["issue_id"])
    assert Repo.aggregate(Ep.Monitoring.Pending, :count) == 0
  end

  test "global sources and a different backend cannot leak into tenant lists", c do
    global =
      Repo.insert!(%Source{
        backend_id: "test-backend",
        identity_id: c.auth.principal.identity_id,
        status: "active"
      })

    other =
      Repo.insert!(%Source{
        backend_id: "another-backend",
        identity_id: c.auth.principal.identity_id,
        tenant_id: c.tid,
        status: "active"
      })

    assert json_response(post(c.api, "/api/v1/monitoring/observations", observation(other)), 404)[
             "error"
           ] == "not_found"

    result =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(global)), 201)

    Oban.drain_queue(queue: :monitoring)

    assert json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues"), 200)["items"] ==
             []

    assert json_response(
             get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{result["issue_id"]}"),
             404
           )["error"] == "not_found"
  end

  test "bounded pagination, timeline and malformed cursors", c do
    for code <- ["application.exception", "dependency.unavailable", "request.conflict"] do
      assert json_response(
               post(c.api, "/api/v1/monitoring/observations", observation(c.source, code)),
               201
             )["issue_id"]
    end

    Oban.drain_queue(queue: :monitoring)
    page = json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues?limit=2"), 200)
    assert length(page["items"]) == 2

    next =
      json_response(
        get(
          c.api,
          "/api/v1/tenants/#{c.tid}/monitoring/issues?limit=2&cursor=" <>
            URI.encode_www_form(page["next_cursor"])
        ),
        200
      )

    assert length(next["items"]) == 1
    assert next["next_cursor"] == nil
    assert Enum.uniq(Enum.map(page["items"] ++ next["items"], & &1["id"])) |> length() == 3
    id = hd(page["items"])["id"]

    timeline =
      json_response(
        get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/timeline?issue_id=#{id}"),
        200
      )

    assert length(timeline["items"]) == 2
    cursor = Base.url_encode64(Jason.encode!(%{id: id, time: nil, cutoff: []}), padding: false)

    assert json_response(
             get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues?cursor=#{cursor}"),
             422
           )["error"] == "invalid_query"
  end

  test "delivery reporting retains uncertainty and never grants access", c do
    bad = observation(c.source)

    assert json_response(post(c.api, "/api/v1/monitoring/delivery-outcomes", bad), 422)["error"] ==
             "invalid_observation"

    p =
      observation(c.source, "delivery.unknown")
      |> Map.put("related", %{"delivery_attempt_id" => Ecto.UUID.generate()})

    result = json_response(post(c.api, "/api/v1/monitoring/delivery-outcomes", p), 201)
    Oban.drain_queue(queue: :monitoring)

    row =
      json_response(
        get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{result["issue_id"]}"),
        200
      )

    assert row["issue"]["data"]["outcome"] == "unknown"
    assert Repo.aggregate(Ep.Tenancy.Access, :count) == 1
  end

  test "observation input is bounded, normalized and does not create business events", c do
    p = observation(c.source)

    for update <- [
          %{"code" => "not.registered"},
          %{"observed_at" => nil},
          %{"occurrence_count" => 0},
          %{"duration_ms" => -1},
          %{"related" => %{"secret" => Ecto.UUID.generate()}}
        ] do
      assert json_response(
               post(c.api, "/api/v1/monitoring/observations", Map.merge(p, update)),
               422
             )["error"] == "invalid_observation"
    end

    result = json_response(post(c.api, "/api/v1/monitoring/observations", p), 201)

    assert Enum.all?(
             Repo.all(Ep.Events.Event) |> Enum.filter(&(&1.command_id == result["command_id"])),
             &(&1.stream_type == "monitoring_issue" and &1.correlation_id == p["correlation_id"])
           )

    tenant_event = Repo.get!(Ep.Events.Event, hd(c.tenant["event_ids"]))
    assert tenant_event.stream_version == 1
  end

  test "request correlation propagates to accepted business facts and response headers", c do
    correlation = Ecto.UUID.generate()

    api =
      c.api
      |> put_req_header("x-correlation-id", correlation)
      |> put_req_header("idempotency-key", "correlated")

    conn = post(api, "/api/v1/tenants", %{"name" => "Correlated"})
    result = json_response(conn, 201)
    assert get_resp_header(conn, "x-correlation-id") == [correlation]
    assert Repo.get!(Ep.Events.Event, hd(result["event_ids"])).correlation_id == correlation
    assert Process.get(:ep_correlation_id) == nil
  end

  test "a code failure returns safe JSON and preserves an unknown outcome", c do
    result =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    issue = Repo.get!(Ep.Monitoring.Issue, result["issue_id"])

    Repo.update!(
      Ecto.Changeset.change(issue, data: Map.put(issue.data, "count", "invalid guard"))
    )

    correlation = Ecto.UUID.generate()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        response =
          post(
            put_req_header(c.api, "x-correlation-id", correlation),
            "/api/v1/monitoring/observations",
            observation(c.source)
          )

        assert json_response(response, 500) == %{
                 "error" => "internal_error",
                 "outcome" => "unknown",
                 "correlation_id" => correlation
               }

        assert get_resp_header(response, "cache-control") == ["no-store"]
      end)

    assert log =~ "ep_request_failed"
    refute log =~ "invalid guard"
    assert Repo.aggregate(Ep.Monitoring.Pending, :count) == 2
    assert Process.get(:ep_correlation_id) == nil
  end

  test "operator source provisioning creates no login channel or user grant", c do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Ep.Monitoring.Source.run(["new-backend", c.tid])
      end)

    assert output =~ "Monitoring source:"
    source = Repo.get_by!(Source, backend_id: "new-backend")
    identity = Repo.get!(Ep.Auth.Identity, source.identity_id)
    assert is_nil(identity.email) and is_nil(identity.verified_at)
    assert Repo.get!(Ep.Auth.Party, identity.party_id).kind == "machine"
    assert Repo.aggregate(Ep.Auth.Session, :count) == 1
    assert Repo.aggregate(Ep.Tenancy.Access, :count) == 1
  end

  test "source flood control returns 429 but still permits a known replay", c do
    p = observation(c.source)
    json_response(post(c.api, "/api/v1/monitoring/observations", p), 201)
    now = DateTime.utc_now()

    rows =
      for i <- 1..599 do
        %{
          id: Ecto.UUID.generate(),
          identity_id: c.source.identity_id,
          command_type: "Monitoring:" <> c.source.id,
          idempotency_key: "rate-#{i}",
          fingerprint: <<0>>,
          result: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Ep.Events.CommandReceipt, rows)

    assert json_response(
             post(c.api, "/api/v1/monitoring/observations", observation(c.source)),
             429
           )["error"] == "rate_limited"

    assert json_response(post(c.api, "/api/v1/monitoring/observations", p), 200)["replayed"]
  end

  test "resolution requires an approved reason and recurrence reopens without duplicating", c do
    result =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    id = result["issue_id"]
    api = put_req_header(c.api, "idempotency-key", "resolve")
    path = "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}/actions"

    assert json_response(
             post(api, path, %{
               "action" => "acknowledge",
               "expected_version" => 2,
               "owner_identity_id" => "secret@example.test"
             }),
             422
           )["error"] == "invalid_action"

    assert json_response(post(api, path, %{"action" => "resolve", "expected_version" => 2}), 422)[
             "error"
           ] == "invalid_action"

    json_response(
      post(api, path, %{"action" => "resolve", "expected_version" => 2, "reason" => "corrected"}),
      200
    )

    next =
      json_response(post(c.api, "/api/v1/monitoring/observations", observation(c.source)), 201)

    assert next["issue_id"] == id
    Oban.drain_queue(queue: :monitoring)

    data =
      json_response(get(c.api, "/api/v1/tenants/#{c.tid}/monitoring/issues/#{id}"), 200)["issue"][
        "data"
      ]

    assert data["state"] == "open"
    assert data["count"] == 2
  end
end
