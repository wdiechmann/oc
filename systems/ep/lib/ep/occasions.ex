defmodule Ep.Occasions do
  @moduledoc "Tenant-authorized occasion creation; administration is separate from participation."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Auth.Principal
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Occasions.{Admin, Directory, Occasion}
  alias Ep.Projections.Control
  alias Ep.Tenancy.{Access, Tenant}

  def create(%Principal{} = principal, tenant_id, params, key) do
    with {:ok, tenant_id} <- uuid(tenant_id),
         {:ok, attrs} <- validate(params),
         :ok <- key_valid(key) do
      fingerprint =
        :crypto.hash(:sha256, :erlang.term_to_binary({"CreateOccasion", tenant_id, attrs}))

      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        authorize_tenant!(principal, tenant_id)
        Events.lock!("command:" <> identity.id <> ":CreateOccasion:" <> key)

        receipt =
          Repo.get_by(CommandReceipt,
            identity_id: identity.id,
            command_type: "CreateOccasion",
            idempotency_key: key
          )

        case receipt do
          nil ->
            %{result: accept!(identity.id, tenant_id, attrs, key, fingerprint), replayed: false}

          %{fingerprint: ^fingerprint, result: result} ->
            %{result: result, replayed: true}

          _ ->
            Repo.rollback(:idempotency_conflict)
        end
      end)
    end
  end

  def list(%Principal{} = principal, tenant_id) do
    with {:ok, tenant_id} <- uuid(tenant_id) do
      Repo.transaction(fn ->
        Auth.lock_principal!(principal)
        authorize_tenant!(principal, tenant_id)
        running!(tenant_id)

        items =
          Repo.all(
            from(d in Directory,
              where: d.tenant_id == ^tenant_id,
              order_by: [asc: d.name, asc: d.occasion_id]
            )
          )

        pending =
          Repo.exists?(
            from(o in Outbox,
              join: e in Ep.Events.Event,
              on: e.id == o.event_id,
              where:
                o.tenant_id == ^tenant_id and e.stream_type == "occasion" and
                  is_nil(o.delivered_at)
            )
          )

        %{status: if(pending, do: :pending, else: :ready), occasions: Enum.map(items, &present/1)}
      end)
    end
  end

  def get(%Principal{} = principal, tenant_id, occasion_id) do
    with {:ok, tenant_id} <- uuid(tenant_id), {:ok, occasion_id} <- uuid(occasion_id) do
      Repo.transaction(fn ->
        Auth.lock_principal!(principal)

        tenant =
          Repo.one(
            from(t in Tenant,
              where: t.id == ^tenant_id and t.status == "active",
              lock: "FOR SHARE"
            )
          )

        unless tenant, do: Repo.rollback(:not_found)
        access = tenant_admin(principal, tenant_id)

        admin =
          Repo.one(
            from(a in Admin,
              where:
                a.tenant_id == ^tenant_id and a.occasion_id == ^occasion_id and
                  a.identity_id == ^principal.identity_id and a.status == "active",
              lock: "FOR SHARE"
            )
          )

        unless access || admin, do: Repo.rollback(:not_found)
        occasion = Repo.get_by(Occasion, tenant_id: tenant_id, id: occasion_id)
        unless occasion, do: Repo.rollback(:not_found)
        running!(tenant_id)

        case Repo.get_by(Directory, tenant_id: tenant_id, occasion_id: occasion_id) do
          nil ->
            %{
              status: :pending,
              tenant_id: tenant_id,
              occasion_id: occasion_id,
              can_manage_recruitment: true,
              can_manage_admins: not is_nil(access)
            }

          row ->
            present(row)
            |> Map.put(:can_manage_admins, not is_nil(access))
            |> Map.put(:can_manage_recruitment, true)
        end
      end)
    end
  end

  defp authorize_tenant!(principal, tenant_id) do
    tenant =
      Repo.one(
        from(t in Tenant, where: t.id == ^tenant_id and t.status == "active", lock: "FOR SHARE")
      )

    unless tenant && tenant_admin(principal, tenant_id), do: Repo.rollback(:not_found)
  end

  defp tenant_admin(principal, tenant_id) do
    Repo.one(
      from(a in Access,
        where:
          a.tenant_id == ^tenant_id and a.identity_id == ^principal.identity_id and
            a.status == "active" and a.role == "tenant_admin",
        lock: "FOR SHARE"
      )
    )
  end

  defp running!(tenant_id) do
    control =
      Repo.one(
        from(c in Control,
          where: c.tenant_id == ^tenant_id and c.name == "occasion_directory",
          lock: "FOR SHARE"
        )
      )

    if control && control.state != "running", do: Repo.rollback(:view_stopped)
  end

  defp accept!(identity_id, tenant_id, attrs, key, fingerprint) do
    unless DateTime.compare(attrs.expires_at, DateTime.utc_now()) == :gt,
      do: Repo.rollback(:invalid_expiry)

    Events.lock!("occasion-slug:" <> tenant_id <> ":" <> attrs.slug)

    if Repo.exists?(
         from(o in Occasion, where: o.tenant_id == ^tenant_id and o.slug == ^attrs.slug)
       ),
       do: Repo.rollback(:slug_taken)

    # The control is initialized only on first creation, without reactivating stopped views.
    Events.lock!("occasion-control:" <> tenant_id)

    unless Repo.get_by(Control, tenant_id: tenant_id, name: "occasion_directory"),
      do: Repo.insert!(%Control{tenant_id: tenant_id, name: "occasion_directory"})

    occasion =
      Repo.insert!(%Occasion{
        tenant_id: tenant_id,
        name: attrs.name,
        slug: attrs.slug,
        expires_at: attrs.expires_at,
        creator_identity_id: identity_id
      })

    command_id = Ecto.UUID.generate()

    facts = [
      {"OccasionCreated",
       %{
         "name" => attrs.name,
         "slug" => attrs.slug,
         "status" => "draft",
         "recruitment_state" => "closed",
         "expires_at" => DateTime.to_iso8601(attrs.expires_at)
       }}
    ]

    facts =
      if attrs.assign_self do
        Repo.insert!(%Admin{
          tenant_id: tenant_id,
          occasion_id: occasion.id,
          identity_id: identity_id
        })

        facts ++
          [{"OccasionAdminGranted", %{"identity_id" => identity_id, "role" => "occasion_admin"}}]
      else
        facts
      end

    events =
      Events.append!(
        %{
          scope: "occasion",
          scope_key: "tenant:" <> tenant_id <> ":occasion:" <> occasion.id,
          tenant_id: tenant_id,
          occasion_id: occasion.id,
          stream_type: "occasion",
          stream_id: occasion.id,
          actor_identity_id: identity_id,
          command_id: command_id,
          correlation_id: command_id
        },
        facts
      )

    Enum.each(events, fn event ->
      Repo.insert!(%Outbox{event_id: event.id, tenant_id: tenant_id})
    end)

    Oban.insert!(Ep.Projections.OccasionWorker.new(%{tenant_id: tenant_id}))

    result = %{
      "tenant_id" => tenant_id,
      "occasion_id" => occasion.id,
      "command_id" => command_id,
      "event_ids" => Enum.map(events, & &1.id),
      "stream_version" => length(events)
    }

    Repo.insert!(%CommandReceipt{
      id: command_id,
      identity_id: identity_id,
      command_type: "CreateOccasion",
      idempotency_key: key,
      fingerprint: fingerprint,
      result: result
    })

    result
  end

  defp present(row),
    do: %{
      status: :ready,
      tenant_id: row.tenant_id,
      occasion_id: row.occasion_id,
      name: row.name,
      slug: row.slug,
      lifecycle: row.status,
      recruitment_state: row.recruitment_state,
      expires_at: row.expires_at,
      source_version: row.source_version,
      updated_at: row.updated_at
    }

  defp validate(params) when is_map(params) do
    name = params["name"]
    slug = params["slug"]
    assign_self = Map.get(params, "assign_self_as_admin", false)

    with true <-
           (is_binary(name) && String.length(String.trim(name)) in 1..120) ||
             {:error, :invalid_name},
         true <-
           (is_binary(slug) && Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug) &&
              byte_size(slug) <= 64) || {:error, :invalid_slug},
         true <- is_boolean(assign_self) || {:error, :invalid_admin_option},
         {:ok, expiry} <- expiry(params["expires_at"]) do
      {:ok, %{name: String.trim(name), slug: slug, expires_at: expiry, assign_self: assign_self}}
    end
  end

  defp validate(_), do: {:error, :invalid_name}

  defp expiry(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} ->
        {:ok, %{time | microsecond: {elem(time.microsecond, 0), 6}}}

      _ ->
        {:error, :invalid_expiry}
    end
  end

  defp expiry(_), do: {:error, :invalid_expiry}

  defp key_valid(key) when is_binary(key),
    do:
      if(Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
        do: :ok,
        else: {:error, :invalid_idempotency_key}
      )

  defp key_valid(_), do: {:error, :invalid_idempotency_key}

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
