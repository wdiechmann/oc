defmodule Ep.Tenancy do
  @moduledoc "Tenant bootstrap commands and authorized directory queries."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Auth.Principal
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Projections.{Control, TenantDirectory}
  alias Ep.Tenancy.{Access, Tenant}

  def create_tenant(%Principal{} = principal, params, key) do
    with {:ok, name} <- tenant_name(params), :ok <- valid_key(key) do
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({"CreateTenant", name}))

      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        Events.lock!("command:" <> identity.id <> ":CreateTenant:" <> key)

        receipt =
          Repo.get_by(CommandReceipt,
            identity_id: identity.id,
            command_type: "CreateTenant",
            idempotency_key: key
          )

        case receipt do
          nil -> %{result: accept_tenant!(identity.id, name, key, fingerprint), replayed: false}
          %{fingerprint: ^fingerprint, result: result} -> %{result: result, replayed: true}
          _ -> Repo.rollback(:idempotency_conflict)
        end
      end)
    end
  end

  def get_tenant(%Principal{} = principal, tenant_id) do
    with {:ok, tenant_id} <- Ecto.UUID.cast(tenant_id) do
      Repo.transaction(fn ->
        Auth.lock_principal!(principal)

        access =
          Repo.one(
            from(a in Access,
              where:
                a.tenant_id == ^tenant_id and a.identity_id == ^principal.identity_id and
                  a.status == "active" and a.role == "tenant_admin",
              lock: "FOR SHARE"
            )
          )

        unless access, do: Repo.rollback(:not_found)

        control =
          Repo.one(
            from(c in Control,
              where: c.tenant_id == ^tenant_id and c.name == "tenant_directory",
              lock: "FOR SHARE"
            )
          )

        unless control && control.state == "running", do: Repo.rollback(:view_stopped)

        case Repo.get_by(TenantDirectory, tenant_id: tenant_id) do
          nil ->
            %{status: :pending, tenant_id: tenant_id}

          row ->
            %{
              status: :ready,
              tenant_id: row.tenant_id,
              name: row.name,
              source_version: row.source_version,
              updated_at: row.updated_at
            }
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp accept_tenant!(identity_id, name, key, fingerprint) do
    command_id = Ecto.UUID.generate()
    tenant = Repo.insert!(%Tenant{name: name, creator_identity_id: identity_id})
    Repo.insert!(%Access{tenant_id: tenant.id, identity_id: identity_id, role: "tenant_admin"})
    Repo.insert!(%Control{tenant_id: tenant.id, name: "tenant_directory"})

    facts = [
      {"TenantCreated", %{"name" => name, "creator_identity_id" => identity_id}},
      {"TenantAdminGranted", %{"identity_id" => identity_id, "role" => "tenant_admin"}}
    ]

    events =
      Events.append!(
        %{
          scope: "tenant",
          scope_key: "tenant:" <> tenant.id,
          tenant_id: tenant.id,
          stream_type: "tenant",
          stream_id: tenant.id,
          actor_identity_id: identity_id,
          command_id: command_id,
          correlation_id: command_id
        },
        facts
      )

    Enum.each(events, fn event ->
      Repo.insert!(%Outbox{event_id: event.id, tenant_id: tenant.id})
    end)

    Oban.insert!(Ep.Projections.TenantWorker.new(%{tenant_id: tenant.id}))

    result = %{
      "tenant_id" => tenant.id,
      "command_id" => command_id,
      "event_ids" => Enum.map(events, & &1.id),
      "stream_version" => 2
    }

    Repo.insert!(%CommandReceipt{
      id: command_id,
      identity_id: identity_id,
      command_type: "CreateTenant",
      idempotency_key: key,
      fingerprint: fingerprint,
      result: result
    })

    result
  end

  defp tenant_name(%{"name" => name}) when is_binary(name) do
    name = String.trim(name)
    if String.length(name) in 1..120, do: {:ok, name}, else: {:error, :invalid_name}
  end

  defp tenant_name(_), do: {:error, :invalid_name}

  defp valid_key(key) when is_binary(key) do
    if Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
      do: :ok,
      else: {:error, :invalid_idempotency_key}
  end

  defp valid_key(_), do: {:error, :invalid_idempotency_key}
end
