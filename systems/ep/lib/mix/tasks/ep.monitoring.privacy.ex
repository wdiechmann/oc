defmodule Mix.Tasks.Ep.Monitoring.Privacy do
  @shortdoc "Apply live monitoring retention or an authorized subject erasure"
  use Mix.Task
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {:ok, principal} = Ep.Auth.authenticate(System.fetch_env!("EP_OPERATOR_BEARER"))

    {:ok, _} =
      Ep.Repo.transaction(fn ->
        Ep.Monitoring.Access.require_permission!(principal, "global", "privacy_operator")
      end)

    case args do
      ["retain"] ->
        IO.puts(Jason.encode!(Ep.Monitoring.Privacy.retain()))

      ["erase", id] ->
        IO.puts(Jason.encode!(Ep.Monitoring.Privacy.erase(id)))

      ["backfill"] ->
        Ep.Monitoring.Privacy.backfill()
        Mix.shell().info("Monitoring subject index backfilled")

      _ ->
        Mix.raise("Expected retain | erase IDENTITY_UUID | backfill")
    end
  end
end
