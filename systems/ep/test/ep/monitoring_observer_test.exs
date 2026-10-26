defmodule Ep.MonitoringObserverTest do
  use ExUnit.Case, async: true
  alias Ep.Monitoring.Observer

  test "telemetry reduces failures to bounded counters without retaining request or SQL content" do
    table = :ets.new(:observer_test, [:set, :public])
    conn = %{request_path: "/api/v1/tenants", status: 500}
    duration = System.convert_time_unit(1500, :millisecond, :native)

    Observer.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: duration},
      %{conn: conn},
      table
    )

    Observer.handle_event(
      [:ep, :repo, :query],
      %{queue_time: duration},
      %{result: {:error, "SecretSqlMarker"}},
      table
    )

    Observer.handle_event(
      [:oban, :job, :exception],
      %{},
      %{state: :failure, job: %{worker: "Ep.Outbox.Worker", attempt: 5, max_attempts: 5}},
      table
    )

    Observer.handle_event(
      [:oban, :job, :exception],
      %{},
      %{state: :failure, job: %{worker: "Ep.Monitoring.Worker", attempt: 5, max_attempts: 5}},
      table
    )

    Observer.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: duration},
      %{conn: %{conn | request_path: "/api/v1/monitoring/observations"}},
      table
    )

    assert Map.new(:ets.tab2list(table)) == %{
             requests: 1,
             errors: 1,
             slow_requests: 1,
             database_errors: 1,
             pool_pressure: 1,
             exhausted_jobs: 1
           }
  end
end
