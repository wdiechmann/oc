defmodule Mix.Tasks.Ep.Monitoring.Grant do
  @shortdoc "Operator bootstrap: grant/revoke an explicit restricted monitoring permission"
  use Mix.Task
  import Ecto.Query
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [identity, permission, scope | rest]
      when permission in ["platform_monitor", "diagnostics", "privacy_operator"] ->
        {:ok, identity} = Ecto.UUID.cast(identity)

        unless scope == "global" ||
                 Regex.match?(~r/^tenant:[0-9a-f-]{36}(:occasion:[0-9a-f-]{36})?$/, scope),
               do: Mix.raise("Invalid scope")

        status = if rest == ["--revoke"], do: "revoked", else: "active"
        unless rest in [[], ["--revoke"]], do: Mix.raise("Unknown option")

        {:ok, _} =
          Ep.Repo.transaction(fn ->
            account =
              Ep.Repo.one(
                from i in Ep.Auth.Identity,
                  where: i.id == ^identity and i.status == "active" and not is_nil(i.verified_at)
              )

            unless account, do: Mix.raise("An active verified operator identity is required")

            row =
              Ep.Repo.get_by(Ep.Monitoring.Permission,
                identity_id: identity,
                scope_key: scope,
                permission: permission
              )

            if row,
              do: Ep.Repo.update!(Ecto.Changeset.change(row, status: status)),
              else:
                Ep.Repo.insert!(%Ep.Monitoring.Permission{
                  identity_id: identity,
                  scope_key: scope,
                  permission: permission,
                  status: status
                })
          end)

        Mix.shell().info(
          "Restricted monitoring permission updated; record operator approval in the deployment log"
        )

      _ ->
        Mix.raise(
          "Expected IDENTITY_UUID platform_monitor|diagnostics|privacy_operator global|tenant:UUID[:occasion:UUID] [--revoke]"
        )
    end
  end
end
