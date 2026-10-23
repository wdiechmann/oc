defmodule Mix.Tasks.Ep.Monitoring.Source do
  @shortdoc "Provision an accountable monitoring source (operator-only)"
  @moduledoc """
  mix ep.monitoring.source BACKEND_ID global
  mix ep.monitoring.source BACKEND_ID TENANT_UUID [OCCASION_UUID]

  Prints the non-secret source UUID. Creates a machine identity with no login channel
  and no administrator grants. Backend token provisioning remains separate.
  Revoke a source through an operator change to monitoring_source.status.
  """
  use Mix.Task
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {backend, tid, oid} =
      case args do
        [backend, "global"] -> {backend, nil, nil}
        [backend, tid] -> {backend, Ecto.UUID.cast!(tid), nil}
        [backend, tid, oid] -> {backend, Ecto.UUID.cast!(tid), Ecto.UUID.cast!(oid)}
        _ -> Mix.raise("Expected BACKEND_ID global or BACKEND_ID TENANT_UUID [OCCASION_UUID]")
      end

    unless Regex.match?(~r/^[a-z0-9_-]{1,64}$/, backend), do: Mix.raise("Invalid backend ID")

    {:ok, source} =
      Ep.Repo.transaction(fn ->
        if tid && !Ep.Repo.get(Ep.Tenancy.Tenant, tid), do: Mix.raise("Unknown tenant")

        if oid && !Ep.Repo.get_by(Ep.Occasions.Occasion, id: oid, tenant_id: tid),
          do: Mix.raise("Unknown occasion in tenant")

        party = Ep.Repo.insert!(%Ep.Auth.Party{kind: "machine"})
        identity = Ep.Repo.insert!(%Ep.Auth.Identity{party_id: party.id})

        Ep.Repo.insert!(%Ep.Monitoring.Source{
          backend_id: backend,
          identity_id: identity.id,
          tenant_id: tid,
          occasion_id: oid,
          status: "active"
        })
      end)

    Mix.shell().info("Monitoring source: #{source.id}")
  end
end
