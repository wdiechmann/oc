defmodule Mix.Tasks.Ep.Monitoring.Backup do
  @shortdoc "Local encrypted backup/inventory and monitoring restore rehearsal"
  use Mix.Task
  @impl Mix.Task
  def run(args) do
    if match?(["apply-ledger", _], args) do
      # Do not expose restored data or run restored jobs before sanitizing it.
      Application.put_env(
        :ep,
        EpWeb.Endpoint,
        Keyword.put(Application.fetch_env!(:ep, EpWeb.Endpoint), :server, false)
      )

      Application.put_env(:ep, :monitoring_recovery_enabled, false)
      Application.put_env(:ep, :monitoring_observer_enabled, false)
      Application.put_env(:ep, :monitoring_retention_enabled, false)

      Application.put_env(
        :ep,
        Oban,
        Application.fetch_env!(:ep, Oban)
        |> Keyword.put(:queues, false)
        |> Keyword.put(:plugins, false)
      )
    end

    Mix.Task.run("app.start")

    result =
      case args do
        ["capture", output] ->
          operator = authorize!()
          Ep.Monitoring.Backup.capture(output, operator.identity_id)

        ["ledger", output] ->
          authorize!()
          Ep.Monitoring.Backup.ledger(output)

        ["worklist", ledger | manifests] ->
          authorize!()
          Ep.Monitoring.Backup.pending_actions(ledger, manifests)

        ["restore-local", input, manifest, ledger, sandbox] ->
          authorize!()
          Ep.Monitoring.Backup.restore_local(input, manifest, ledger, sandbox)

        ["apply-ledger", ledger] ->
          Ep.Monitoring.Backup.apply_ledger(ledger)

        _ ->
          Mix.raise(
            "Expected capture OUTPUT | ledger OUTPUT | worklist LEDGER MANIFEST... | restore-local INPUT MANIFEST LEDGER SANDBOX | apply-ledger LEDGER"
          )
      end

    IO.puts(Jason.encode!(result))
  end

  defp authorize! do
    {:ok, p} = Ep.Auth.authenticate(System.fetch_env!("EP_OPERATOR_BEARER"))

    {:ok, _} =
      Ep.Repo.transaction(fn ->
        Ep.Monitoring.Access.require_permission!(p, "global", "privacy_operator")
      end)

    p
  end
end
