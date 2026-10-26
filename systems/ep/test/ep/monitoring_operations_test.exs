defmodule Ep.MonitoringOperationsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Monitoring.{Configuration, Alerts, Access, Permission, Privacy}

  setup do
    owner = sign_in()
    owner = Map.put(owner, :email, Repo.get!(Ep.Auth.Identity, owner.principal.identity_id).email)

    {:ok, %{result: tenant}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Operations"}, "tenant")

    tid = tenant["tenant_id"]

    {:ok, result} =
      Configuration.register(owner.principal, tid, %{"backend_id" => "test-backend"}, "source")

    %{owner: owner, tid: tid, source_id: result["source_id"], tenant: tenant}
  end

  defp observation(c, extra \\ %{}) do
    Map.merge(
      %{
        "source_id" => c.source_id,
        "source_observation_id" => Ecto.UUID.generate(),
        "code" => "application.exception",
        "correlation_id" => Ecto.UUID.generate(),
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
      },
      extra
    )
  end

  defp rule(c),
    do: %{
      "source_id" => c.source_id,
      "code" => "application.exception",
      "threshold" => 2,
      "window_seconds" => 60,
      "cooldown_seconds" => 60,
      "enabled" => true,
      "recipient_ids" => [c.owner.principal.identity_id],
      "delivery_backend_id" => "test-backend"
    }

  test "source discovery is backend-bound and registration/revocation are governed", c do
    assert {:ok, %{sources: bindings}} = Configuration.bindings("test-backend")
    assert bindings[Access.scope(c.tid, nil)] == c.source_id
    assert {:ok, %{sources: %{}}} = Configuration.bindings("another-backend")

    assert {:ok, %{"replayed" => true}} =
             Configuration.register(
               c.owner.principal,
               c.tid,
               %{"backend_id" => "test-backend"},
               "source"
             )

    stranger = sign_in()
    assert {:error, :not_found} = Configuration.sources(stranger.principal, c.tid, nil)

    assert {:ok, %{assignees: [%{identity_id: id}]}} =
             Configuration.assignees(c.owner.principal, c.tid, nil)

    assert id == c.owner.principal.identity_id
    assert {:ok, _} = Configuration.revoke(c.owner.principal, c.tid, c.source_id, "revoke")
    assert {:error, :not_found} = Ep.Monitoring.record("test-backend", observation(c))
  end

  test "threshold/cooldown, idempotent claims and ambiguous delivery never auto-resend", c do
    assert {:ok, _} = Alerts.configure(c.owner.principal, c.tid, rule(c), "rule")
    first = observation(c)
    assert {:ok, _} = Ep.Monitoring.record("test-backend", first)
    assert Repo.aggregate(Ep.Monitoring.Alert, :count) == 0
    assert {:ok, _} = Ep.Monitoring.record("test-backend", observation(c))
    assert Repo.aggregate(Ep.Monitoring.Alert, :count) == 1
    assert {:ok, _} = Ep.Monitoring.record("test-backend", observation(c))
    assert Repo.aggregate(Ep.Monitoring.Alert, :count) == 1
    request_id = Ecto.UUID.generate()

    assert {:ok, %{alerts: [material]}} =
             Alerts.claim("test-backend", %{"request_id" => request_id})

    assert material.recipients == [c.owner.email]

    assert {:ok, %{alerts: [^material]}} =
             Alerts.claim("test-backend", %{"request_id" => request_id})

    assert {:ok, %{alerts: []}} =
             Alerts.claim("another-backend", %{"request_id" => Ecto.UUID.generate()})

    assert {:ok, _} =
             Alerts.outcome("test-backend", material.alert_id, %{
               "attempt_id" => material.attempt_id,
               "status" => "unknown"
             })

    assert {:ok, %{alerts: []}} =
             Alerts.claim("test-backend", %{"request_id" => Ecto.UUID.generate()})

    assert {:ok, %{replayed: true}} =
             Alerts.outcome("test-backend", material.alert_id, %{
               "attempt_id" => material.attempt_id,
               "status" => "unknown"
             })

    refute Enum.any?(
             Repo.all(Ep.Events.Details),
             &String.contains?(Jason.encode!(&1.payload), c.owner.email)
           )
  end

  test "suppression preserves observations but prevents new notifications", c do
    {:ok, r} = Alerts.configure(c.owner.principal, c.tid, rule(c), "rule")

    params = %{
      "expected_version" => 1,
      "reason" => "maintenance",
      "until" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 600, :second))
    }

    assert {:ok, _} =
             Alerts.suppress(c.owner.principal, c.tid, r["rule_id"], params, "suppression")

    assert {:ok, _} =
             Ep.Monitoring.record("test-backend", observation(c, %{"occurrence_count" => 10}))

    assert Repo.aggregate(Ep.Monitoring.Issue, :count) == 1
    assert Repo.aggregate(Ep.Monitoring.Alert, :count) == 0
  end

  test "diagnostics require explicit permission, exclude raw text and expire independently", c do
    diagnostic = %{
      "exception_class" => "RuntimeError",
      "frames" => [%{"file" => "sample.rb", "line" => 4, "label" => "submit"}]
    }

    {:ok, result} =
      Ep.Monitoring.record("test-backend", observation(c, %{"diagnostic" => diagnostic}))

    id = hd(result["event_ids"])
    assert {:error, :not_found} = Ep.Monitoring.Diagnostics.read(c.owner.principal, c.tid, id)

    Repo.insert!(%Permission{
      identity_id: c.owner.principal.identity_id,
      scope_key: Access.scope(c.tid, nil),
      permission: "diagnostics",
      status: "active"
    })

    assert {:ok, %{diagnostic: ^diagnostic}} =
             Ep.Monitoring.Diagnostics.read(c.owner.principal, c.tid, id)

    assert {:error, _} =
             Ep.Monitoring.record(
               "test-backend",
               observation(c, %{"diagnostic" => Map.put(diagnostic, "message", "private text")})
             )

    Oban.drain_queue(queue: :monitoring)

    {:ok, %{items: [row]}} =
      Ep.Monitoring.Queries.list(c.owner.principal, c.tid, "observation", %{})

    refute Map.has_key?(row.data, "diagnostic")

    assert %{diagnostics_removed: 1} =
             Privacy.retain(DateTime.add(DateTime.utc_now(), 31 * 86_400, :second))

    assert {:error, :not_found} = Ep.Monitoring.Diagnostics.read(c.owner.principal, c.tid, id)
  end

  test "erasure clears live links and replay cannot restore suppressed content", c do
    {:ok, result} =
      Ep.Monitoring.record(
        "test-backend",
        observation(c, %{"related" => %{"business_command_id" => c.tenant["command_id"]}})
      )

    issue_id = result["issue_id"]
    Oban.drain_queue(queue: :monitoring)
    assert %{affected_events: count} = Privacy.erase(c.owner.principal.identity_id)
    assert count >= 2
    Oban.drain_queue(queue: :monitoring)
    {:ok, %{issue: row}} = Ep.Monitoring.Queries.detail(c.owner.principal, c.tid, issue_id)
    assert row.data["related"] == %{}
    refute Jason.encode!(row.data) =~ c.tenant["command_id"]

    for id <- result["event_ids"] do
      assert Repo.get!(Ep.Events.Details, id).payload["privacy_erased"]
    end
  end

  test "late buffered observations cannot reintroduce erased diagnostics or links", c do
    Privacy.erase(c.owner.principal.identity_id)
    diagnostic = %{"exception_class" => "PrivacyMarker", "frames" => []}

    {:ok, result} =
      Ep.Monitoring.record(
        "test-backend",
        observation(c, %{
          "related" => %{"business_command_id" => c.tenant["command_id"]},
          "diagnostic" => diagnostic
        })
      )

    id = hd(result["event_ids"])
    assert Repo.get!(Ep.Events.Details, id).payload["privacy_erased"]
    refute Repo.get(Ep.Monitoring.Diagnostic, id)
    Oban.drain_queue(queue: :monitoring)

    assert {:ok, %{items: []}} =
             Ep.Monitoring.Queries.list(c.owner.principal, c.tid, "issue", %{})
  end

  test "retention keeps checkpoints so later allowed observations still project", c do
    {:ok, result} = Ep.Monitoring.record("test-backend", observation(c))
    Oban.drain_queue(queue: :monitoring)

    assert %{events_redacted: count} =
             Privacy.retain(DateTime.add(DateTime.utc_now(), 91 * 86_400, :second))

    assert count >= 2

    assert {:error, :not_found} =
             Ep.Monitoring.Queries.detail(c.owner.principal, c.tid, result["issue_id"])

    {:ok, _} = Ep.Monitoring.record("test-backend", observation(c))
    Oban.drain_queue(queue: :monitoring)

    assert {:ok, %{items: [%{data: %{"count" => 1, "state" => "open"}}]}} =
             Ep.Monitoring.Queries.list(c.owner.principal, c.tid, "issue", %{})
  end

  test "platform access alone does not disclose global diagnostics", c do
    Repo.insert!(%Permission{
      identity_id: c.owner.principal.identity_id,
      scope_key: "global",
      permission: "platform_monitor",
      status: "active"
    })

    {:ok, global} =
      Configuration.register(
        c.owner.principal,
        nil,
        %{"backend_id" => "test-backend"},
        "global-source"
      )

    input =
      observation(c, %{
        "source_id" => global["source_id"],
        "diagnostic" => %{"exception_class" => "RestrictedTrace", "frames" => []}
      })

    {:ok, accepted} = Ep.Monitoring.record("test-backend", input)
    id = hd(accepted["event_ids"])
    assert {:error, :not_found} = Ep.Monitoring.Diagnostics.read(c.owner.principal, nil, id)

    Repo.insert!(%Permission{
      identity_id: c.owner.principal.identity_id,
      scope_key: "global",
      permission: "diagnostics",
      status: "active"
    })

    assert {:ok, %{event_id: ^id}} = Ep.Monitoring.Diagnostics.read(c.owner.principal, nil, id)
  end
end
