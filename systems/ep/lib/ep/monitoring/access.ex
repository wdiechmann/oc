defmodule Ep.Monitoring.Access do
  @moduledoc "Explicit restricted monitoring permissions; tenant administration does not imply platform/diagnostic access."
  import Ecto.Query
  alias Ep.{Auth, Repo, Monitoring}
  alias Ep.Monitoring.Permission
  def scope(nil, _), do: "global"
  def scope(tid, nil), do: "tenant:" <> tid
  def scope(tid, oid), do: "tenant:#{tid}:occasion:#{oid}"
  def platform!(principal), do: require_permission!(principal, "global", "platform_monitor")

  def diagnostic!(principal, tid, oid) do
    if tid, do: Monitoring.authorize!(principal, tid, oid), else: platform!(principal)

    scopes = if tid, do: Enum.uniq([scope(tid, nil), scope(tid, oid)]), else: ["global"]
    Auth.lock_principal!(principal)

    row =
      Repo.one(
        from p in Permission,
          where:
            p.identity_id == ^principal.identity_id and p.permission == "diagnostics" and
              p.scope_key in ^scopes and p.status == "active",
          limit: 1,
          lock: "FOR SHARE"
      )

    unless row, do: Repo.rollback(:not_found)

    :ok
  end

  def require_permission!(principal, scope, permission) do
    Auth.lock_principal!(principal)

    row =
      Repo.one(
        from p in Permission,
          where:
            p.identity_id == ^principal.identity_id and p.scope_key == ^scope and
              p.permission == ^permission and p.status == "active",
          lock: "FOR SHARE"
      )

    unless row, do: Repo.rollback(:not_found)
    :ok
  end
end
