defmodule Ep.MonitoringConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Ep.Repo
  alias Ep.Monitoring.{Issue, Pending, Source, View}

  test "independent connections deduplicate reports and serialize counts and projection" do
    source =
      Sandbox.unboxed_run(Repo, fn ->
        party = Repo.insert!(%Ep.Auth.Party{kind: "machine"})
        identity = Repo.insert!(%Ep.Auth.Identity{party_id: party.id})

        Repo.insert!(%Source{
          backend_id: "race-backend",
          identity_id: identity.id,
          status: "active"
        })
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(source) end) end)
    supervisor = start_supervised!({Task.Supervisor, []})

    input = %{
      "source_id" => source.id,
      "source_observation_id" => Ecto.UUID.generate(),
      "code" => "application.exception",
      "correlation_id" => Ecto.UUID.generate(),
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    results =
      race(supervisor, [
        fn -> Ep.Monitoring.record("race-backend", input) end,
        fn -> Ep.Monitoring.record("race-backend", input) end
      ])

    assert Enum.sort(Enum.map(results, fn {:ok, row} -> row["replayed"] end)) == [false, true]
    [{:ok, result} | _] = results
    issue_id = result["issue_id"]

    results =
      race(
        supervisor,
        for _ <- 1..2 do
          fn ->
            Ep.Monitoring.record(
              "race-backend",
              Map.put(input, "source_observation_id", Ecto.UUID.generate())
            )
          end
        end
      )

    assert Enum.all?(results, &match?({:ok, _}, &1))

    results =
      race(supervisor, [
        fn -> Ep.Monitoring.Projector.deliver(issue_id) end,
        fn -> Ep.Monitoring.Projector.deliver(issue_id) end
      ])

    assert Enum.sort(Enum.map(results, fn {:ok, count} -> count end)) == [0, 4]

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.get!(Issue, issue_id).version == 4
      assert Repo.get!(View, issue_id).data["count"] == 3
      assert Repo.aggregate(from(p in Pending, where: p.issue_id == ^issue_id), :count) == 0
    end)
  end

  test "internal EP capture records failures without recursive reporting" do
    source =
      Sandbox.unboxed_run(Repo, fn ->
        party = Repo.insert!(%Ep.Auth.Party{kind: "machine"})
        identity = Repo.insert!(%Ep.Auth.Identity{party_id: party.id})
        Repo.insert!(%Source{backend_id: "ep", identity_id: identity.id, status: "active"})
      end)

    previous = Application.get_env(:ep, :monitoring_source_id)
    Application.put_env(:ep, :monitoring_source_id, source.id)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ep, :monitoring_source_id, previous),
        else: Application.delete_env(:ep, :monitoring_source_id)

      Sandbox.unboxed_run(Repo, fn -> cleanup(source) end)
    end)

    correlation = Ecto.UUID.generate()

    ExUnit.CaptureLog.capture_log(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        assert :ok = Ep.Monitoring.capture_exception(correlation)
        assert :ok = Ep.Monitoring.capture_exception(correlation, true)
        issue = Repo.get_by!(Issue, source_id: source.id)
        assert issue.data["count"] == 1
        assert issue.data["correlation_id"] == correlation

        conn =
          Plug.Test.conn(:get, "/health/ready")
          |> Plug.Conn.put_req_header("x-correlation-id", correlation)

        response = EpWeb.ApiBoundary.protect(conn, fn _ -> raise "PrivateConfigErrorMarker" end)
        assert response.status == 500
        assert Jason.decode!(response.resp_body)["correlation_id"] == correlation
        refute response.resp_body =~ "PrivateConfigErrorMarker"
        assert Repo.get!(Issue, issue.id).data["count"] == 2

        details =
          Repo.all(
            from d in Ep.Events.Details,
              join: e in Ep.Events.Event,
              on: e.id == d.event_id,
              where: e.stream_id == ^issue.id,
              select: d.payload
          )

        refute Jason.encode!(details) =~ "PrivateConfigErrorMarker"
      end)
    end)
  end

  defp race(supervisor, actions) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(actions, fn action ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:ready, self()})

          receive do
            {:go, ^barrier} -> Sandbox.unboxed_run(Repo, action)
          end
        end)
      end)

    Enum.each(tasks, fn t -> assert_receive {:ready, pid} when pid == t.pid end)
    Enum.each(tasks, fn t -> send(t.pid, {:go, barrier}) end)
    Task.await_many(tasks, 15_000)
  end

  defp cleanup(source) do
    identity = Repo.get!(Ep.Auth.Identity, source.identity_id)
    ids = Repo.all(from i in Issue, where: i.source_id == ^source.id, select: i.id)
    event_ids = Repo.all(from e in Ep.Events.Event, where: e.stream_id in ^ids, select: e.id)

    Repo.transaction(fn ->
      Repo.delete_all(from j in Oban.Job, where: fragment("?->>'issue_id'", j.args) in ^ids)
      Repo.delete_all(from v in View, where: v.issue_id in ^ids)
      Repo.delete_all(from p in Pending, where: p.issue_id in ^ids)
      Repo.delete_all(from s in Ep.Monitoring.Subject, where: s.event_id in ^event_ids)
      Repo.delete_all(from d in Ep.Monitoring.Diagnostic, where: d.event_id in ^event_ids)
      Repo.delete_all(from d in Ep.Events.Details, where: d.event_id in ^event_ids)
      Repo.delete_all(from e in Ep.Events.Event, where: e.id in ^event_ids)
      Repo.delete_all(from h in Ep.Events.StreamHead, where: h.stream_id in ^ids)
      Repo.delete_all(from i in Issue, where: i.id in ^ids)
      Repo.delete_all(from c in Ep.Events.CommandReceipt, where: c.identity_id == ^identity.id)
      Repo.delete!(source)
      Repo.delete!(identity)
      Repo.delete_all(from p in Ep.Auth.Party, where: p.id == ^identity.party_id)
    end)
  end
end
