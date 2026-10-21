defmodule Ep.Recruitment do
  @moduledoc "Explicit recruitment lifecycle and minimal verified-user intake; no applicant admission."
  import Ecto.Query
  alias Ep.{Auth, Events, Repo}
  alias Ep.Auth.Principal
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Occasions.{Admin, Directory, Occasion}
  alias Ep.Projections.Control
  alias Ep.Tenancy.{Access, Tenant}
  alias Ep.Recruitment.Application, as: Intake

  def manage(%Principal{} = principal, tid, oid) do
    with :ok <- ids(tid, oid) do
      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        authorize!(identity.id, tid, oid)
        occasion = occasion!(tid, oid, "FOR SHARE")

        %{
          tenant_id: tid,
          occasion_id: oid,
          name: occasion.name,
          slug: occasion.slug,
          recruitment_state: occasion.recruitment_state,
          config: occasion.recruitment_config,
          expires_at: occasion.expires_at,
          expired: expired?(occasion)
        }
      end)
    end
  end

  def open(principal, tid, oid, params, key) do
    with {:ok, config} <- config(params) do
      command(principal, tid, oid, "OpenOccasionRecruitment", key, config, true, fn identity,
                                                                                    occasion ->
        if expired?(occasion), do: Repo.rollback(:occasion_expired)
        if occasion.recruitment_state == "open", do: Repo.rollback(:already_open)

        Repo.update!(
          Ecto.Changeset.change(occasion, recruitment_state: "open", recruitment_config: config)
        )

        {%{"recruitment_state" => "open"},
         [{"OccasionRecruitmentOpened", %{"config" => config, "opened_by" => identity.id}}]}
      end)
    end
  end

  def close(principal, tid, oid, params, key) do
    reason = params["reason"]

    if is_binary(reason) && String.length(String.trim(reason)) in 1..500 do
      reason = String.trim(reason)

      command(principal, tid, oid, "CloseOccasionRecruitment", key, reason, true, fn _identity,
                                                                                     occasion ->
        unless occasion.recruitment_state == "open", do: Repo.rollback(:already_closed)
        Repo.update!(Ecto.Changeset.change(occasion, recruitment_state: "closed"))

        {%{"recruitment_state" => "closed"},
         [{"OccasionRecruitmentClosed", %{"reason" => reason}}]}
      end)
    else
      {:error, :invalid_reason}
    end
  end

  def landing(tid, slug) when is_binary(slug) do
    if match?({:ok, _}, Ecto.UUID.cast(tid)) && byte_size(slug) <= 64 do
      Repo.transaction(fn ->
        active_tenant!(tid)

        occasion =
          Repo.one(
            from(o in Occasion, where: o.tenant_id == ^tid and o.slug == ^slug, lock: "FOR SHARE")
          ) || Repo.rollback(:not_found)

        open_intake!(occasion)

        control =
          Repo.one(
            from(c in Control,
              where: c.tenant_id == ^tid and c.name == "occasion_directory",
              lock: "FOR SHARE"
            )
          )

        unless control && control.state == "running", do: Repo.rollback(:view_stopped)
        row = Repo.get_by(Directory, tenant_id: tid, occasion_id: occasion.id)

        if row && row.recruitment_state == "open" &&
             row.recruitment_config == occasion.recruitment_config do
          %{
            status: :ready,
            tenant_id: tid,
            occasion_id: row.occasion_id,
            name: row.name,
            slug: row.slug,
            config: row.recruitment_config
          }
        else
          %{status: :pending}
        end
      end)
    else
      {:error, :not_found}
    end
  end

  def landing(_, _), do: {:error, :not_found}

  def submit(principal, tid, oid, params, key) do
    if params["acknowledge_notice"] == true && is_binary(params["notice_version"]) do
      version = params["notice_version"]

      command(
        principal,
        tid,
        oid,
        "SubmitRecruitmentApplication",
        key,
        version,
        false,
        fn identity, occasion ->
          open_intake!(occasion)

          if occasion.recruitment_config["notice_version"] != version,
            do: Repo.rollback(:policy_changed)

          Events.lock!("recruitment-applicant:" <> oid <> ":" <> identity.id)

          existing =
            Repo.exists?(
              from(a in Intake,
                where:
                  a.tenant_id == ^tid and a.occasion_id == ^oid and a.identity_id == ^identity.id
              )
            )

          if existing, do: Repo.rollback(:already_applied)

          application =
            Repo.insert!(%Intake{
              tenant_id: tid,
              occasion_id: oid,
              identity_id: identity.id,
              notice_version: version
            })

          {%{"application_id" => application.id, "status" => "pending_review"},
           [
             {"RecruitmentApplicationSubmitted",
              %{
                "application_id" => application.id,
                "identity_id" => identity.id,
                "notice_version" => version,
                "status" => "pending_review"
              }}
           ]}
        end
      )
    else
      {:error, :notice_acknowledgment_required}
    end
  end

  def applications(principal, tid, oid) do
    with :ok <- ids(tid, oid) do
      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        authorize!(identity.id, tid, oid)
        occasion!(tid, oid, "FOR SHARE")

        rows =
          Repo.all(
            from(a in Intake,
              join: i in Ep.Auth.Identity,
              on: i.id == a.identity_id,
              where: a.tenant_id == ^tid and a.occasion_id == ^oid,
              order_by: [desc: a.inserted_at, asc: a.id],
              limit: 100,
              select: %{
                application_id: a.id,
                email: i.email,
                status: a.status,
                submitted_at: a.inserted_at
              }
            )
          )

        %{applications: rows}
      end)
    end
  end

  defp command(principal, tid, oid, type, key, attrs, admin?, apply) do
    with :ok <- ids(tid, oid), :ok <- key_valid(key) do
      {:ok, tid} = Ecto.UUID.cast(tid)
      {:ok, oid} = Ecto.UUID.cast(oid)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({type, tid, oid, attrs}))

      Repo.transaction(fn ->
        identity = Auth.lock_principal!(principal)
        active_tenant!(tid)
        if admin?, do: authorize!(identity.id, tid, oid)
        Events.lock!("command:" <> identity.id <> ":" <> type <> ":" <> key)

        case Repo.get_by(CommandReceipt,
               identity_id: identity.id,
               command_type: type,
               idempotency_key: key
             ) do
          nil ->
            # Intake holds SHARE until commit; transitions require UPDATE on this same row.
            occasion = occasion!(tid, oid, if(admin?, do: "FOR UPDATE", else: "FOR SHARE"))
            {result, facts} = apply.(identity, occasion)
            cid = Ecto.UUID.generate()

            events =
              Events.append!(
                %{
                  scope: "occasion",
                  scope_key: "tenant:" <> tid <> ":occasion:" <> oid,
                  tenant_id: tid,
                  occasion_id: oid,
                  stream_type: "occasion",
                  stream_id: oid,
                  actor_identity_id: identity.id,
                  command_id: cid,
                  correlation_id: cid
                },
                facts
              )

            Enum.each(events, fn e -> Repo.insert!(%Outbox{event_id: e.id, tenant_id: tid}) end)
            Oban.insert!(Ep.Projections.OccasionWorker.new(%{tenant_id: tid}))

            result =
              Map.merge(result, %{
                "tenant_id" => tid,
                "occasion_id" => oid,
                "command_id" => cid,
                "event_ids" => Enum.map(events, & &1.id)
              })

            Repo.insert!(%CommandReceipt{
              id: cid,
              identity_id: identity.id,
              command_type: type,
              idempotency_key: key,
              fingerprint: fingerprint,
              result: result
            })

            %{result: result, replayed: false}

          %{fingerprint: ^fingerprint, result: result} ->
            %{result: result, replayed: true}

          _ ->
            Repo.rollback(:idempotency_conflict)
        end
      end)
    end
  end

  defp active_tenant!(tid) do
    row =
      Repo.one(from(t in Tenant, where: t.id == ^tid and t.status == "active", lock: "FOR SHARE"))

    unless row, do: Repo.rollback(:not_found)
  end

  defp authorize!(identity, tid, oid) do
    active_tenant!(tid)

    tenant =
      Repo.one(
        from(a in Access,
          where:
            a.tenant_id == ^tid and a.identity_id == ^identity and a.role == "tenant_admin" and
              a.status == "active",
          lock: "FOR SHARE"
        )
      )

    occasion =
      Repo.one(
        from(a in Admin,
          where:
            a.tenant_id == ^tid and a.occasion_id == ^oid and a.identity_id == ^identity and
              a.status == "active",
          lock: "FOR SHARE"
        )
      )

    unless tenant || occasion, do: Repo.rollback(:not_found)
  end

  defp occasion!(tid, oid, lock) do
    query =
      from(o in Occasion,
        where: o.tenant_id == ^tid and o.id == ^oid and o.status in ["draft", "active"]
      )

    query =
      if lock == "FOR UPDATE",
        do: from(o in query, lock: "FOR UPDATE"),
        else: from(o in query, lock: "FOR SHARE")

    Repo.one(query) || Repo.rollback(:not_found)
  end

  defp expired?(o), do: DateTime.compare(o.expires_at, DateTime.utc_now()) != :gt

  defp open_intake!(o) do
    unless o.status in ["draft", "active"] && o.recruitment_state == "open" && !expired?(o),
      do: Repo.rollback(:recruitment_closed)
  end

  defp ids(tid, oid) do
    if match?({:ok, _}, Ecto.UUID.cast(tid)) && match?({:ok, _}, Ecto.UUID.cast(oid)),
      do: :ok,
      else: {:error, :not_found}
  end

  defp key_valid(key) do
    if is_binary(key) && Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
      do: :ok,
      else: {:error, :invalid_idempotency_key}
  end

  defp config(params) do
    title = params["title"]
    instructions = params["instructions"]
    notice = params["privacy_notice_url"]

    uri =
      case is_binary(notice) && URI.new(notice) do
        {:ok, uri} -> uri
        _ -> %URI{}
      end

    cond do
      !is_binary(title) || String.length(String.trim(title)) not in 1..120 ->
        {:error, :invalid_title}

      !is_binary(instructions) || String.length(String.trim(instructions)) not in 1..2000 ->
        {:error, :invalid_instructions}

      !is_binary(notice) || byte_size(notice) > 2048 || uri.scheme != "https" ||
        !is_binary(uri.host) || uri.host == "" || not is_nil(uri.userinfo) ->
        {:error, :invalid_privacy_notice_url}

      params["confirm_manual_review"] != true ->
        {:error, :review_policy_required}

      true ->
        config = %{
          "title" => String.trim(title),
          "instructions" => String.trim(instructions),
          "privacy_notice_url" => notice,
          "admission" => "pending_manual_review",
          "lead_vouch_required" => true,
          "safeguarding_before_assignment" => true,
          "qualification_checks_before_assignment" => true,
          "intake_schema_version" => 1
        }

        version =
          :crypto.hash(:sha256, :erlang.term_to_binary(config)) |> Base.encode16(case: :lower)

        {:ok, Map.put(config, "notice_version", version)}
    end
  end
end
