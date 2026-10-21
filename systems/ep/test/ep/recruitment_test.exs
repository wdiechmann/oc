defmodule Ep.RecruitmentTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Recruitment.Application, as: Intake

  setup do
    owner = sign_in()
    {:ok, %{result: t}} = Ep.Tenancy.create_tenant(owner.principal, %{"name" => "SL"}, "tenant")

    {:ok, %{result: o}} =
      Ep.Occasions.create(
        owner.principal,
        t["tenant_id"],
        %{
          "name" => "SL2030",
          "slug" => "sl2030",
          "expires_at" => "2032-01-01T00:00:00Z",
          "assign_self_as_admin" => true
        },
        "occasion"
      )

    %{owner: owner, tid: t["tenant_id"], oid: o["occasion_id"]}
  end

  defp config,
    do: %{
      "title" => "Join the camp team",
      "instructions" => "Applications are reviewed by the recruitment team.",
      "privacy_notice_url" => "https://example.test/recruitment-privacy",
      "confirm_manual_review" => true
    }

  defp open(c), do: Ep.Recruitment.open(c.owner.principal, c.tid, c.oid, config(), "open")

  defp submit(c, prospect, version, key \\ "apply"),
    do:
      Ep.Recruitment.submit(
        prospect.principal,
        c.tid,
        c.oid,
        %{
          "notice_version" => version,
          "acknowledge_notice" => true,
          "status" => "accepted",
          "role" => "tenant_admin"
        },
        key
      )

  test "explicit opening persists a scoped fact, configuration and projected public intake", c do
    assert {:error, :recruitment_closed} = Ep.Recruitment.landing(c.tid, "sl2030")
    assert {:ok, %{result: r}} = open(c)
    assert r["recruitment_state"] == "open"
    assert {:ok, %{status: :pending}} = Ep.Recruitment.landing(c.tid, "sl2030")
    assert %{failure: 0} = Oban.drain_queue(queue: :projections)
    assert {:ok, %{config: p, name: "SL2030"}} = Ep.Recruitment.landing(c.tid, "sl2030")

    assert p["admission"] == "pending_manual_review" && p["lead_vouch_required"] &&
             p["safeguarding_before_assignment"]

    assert {:ok, %{replayed: true, result: ^r}} = open(c)

    assert {:error, :already_open} =
             Ep.Recruitment.open(c.owner.principal, c.tid, c.oid, config(), "different-open")

    assert {:error, :idempotency_conflict} =
             Ep.Recruitment.open(
               c.owner.principal,
               c.tid,
               c.oid,
               Map.put(config(), "title", "Changed"),
               "open"
             )
  end

  test "verified applicant submits once for pending review and receives no grant or membership",
       c do
    open(c)
    {:ok, %{config: p}} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)
    prospect = sign_in()
    assert {:ok, %{result: r}} = submit(c, prospect, p["notice_version"])
    assert r["status"] == "pending_review"
    assert {:ok, %{replayed: true, result: ^r}} = submit(c, prospect, p["notice_version"])
    assert {:error, :already_applied} = submit(c, prospect, p["notice_version"], "different")
    assert Repo.aggregate(Intake, :count) == 1
    refute Repo.get_by(Ep.Tenancy.Access, identity_id: prospect.principal.identity_id)
    refute Repo.get_by(Ep.Occasions.Admin, identity_id: prospect.principal.identity_id)
    assert {:error, :not_found} = Ep.Recruitment.applications(prospect.principal, c.tid, c.oid)

    assert {:ok, %{applications: [%{status: "pending_review"}]}} =
             Ep.Recruitment.applications(c.owner.principal, c.tid, c.oid)

    assert %{failure: 0} = Oban.drain_queue(queue: :projections)
  end

  test "closure immediately prevents intake despite stale MV; old accepted receipt remains historical",
       c do
    open(c)
    {:ok, %{config: p}} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)
    prospect = sign_in()
    {:ok, %{result: r}} = submit(c, prospect, p["notice_version"])
    Oban.drain_queue(queue: :projections)

    assert {:ok, %{result: closed}} =
             Ep.Recruitment.close(
               c.owner.principal,
               c.tid,
               c.oid,
               %{"reason" => "Team filled"},
               "close"
             )

    assert closed["recruitment_state"] == "closed"
    assert {:error, :recruitment_closed} = Ep.Recruitment.landing(c.tid, "sl2030")
    assert {:error, :recruitment_closed} = submit(c, sign_in(), p["notice_version"])
    assert {:ok, %{result: ^r, replayed: true}} = submit(c, prospect, p["notice_version"])

    assert {:ok, %{replayed: true}} =
             Ep.Recruitment.close(
               c.owner.principal,
               c.tid,
               c.oid,
               %{"reason" => "Team filled"},
               "close"
             )

    assert Repo.get!(
             Ep.Occasions.Directory,
             Repo.one!(
               from(d in Ep.Occasions.Directory, where: d.occasion_id == ^c.oid, select: d.id)
             )
           ).recruitment_state == "open"
  end

  test "invalid policy, unsafe links and missing acknowledgment cannot mutate intake", c do
    for {field, value, reason} <- [
          {"title", " ", :invalid_title},
          {"instructions", "", :invalid_instructions},
          {"privacy_notice_url", "javascript:alert(1)", :invalid_privacy_notice_url},
          {"confirm_manual_review", false, :review_policy_required}
        ] do
      assert {:error, ^reason} =
               Ep.Recruitment.open(
                 c.owner.principal,
                 c.tid,
                 c.oid,
                 Map.put(config(), field, value),
                 "bad"
               )
    end

    open(c)
    prospect = sign_in()

    assert {:error, :notice_acknowledgment_required} =
             Ep.Recruitment.submit(prospect.principal, c.tid, c.oid, %{}, "no-notice")

    assert {:error, :policy_changed} = submit(c, prospect, "stale-version")
    assert Repo.aggregate(Intake, :count) == 0
  end

  test "changed policy after closing invalidates earlier application forms", c do
    open(c)
    {:ok, %{config: p}} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)
    Ep.Recruitment.close(c.owner.principal, c.tid, c.oid, %{"reason" => "Change policy"}, "close")

    assert {:ok, _} =
             Ep.Recruitment.open(
               c.owner.principal,
               c.tid,
               c.oid,
               Map.put(config(), "instructions", "Updated intake rules"),
               "reopen"
             )

    assert {:error, :policy_changed} = submit(c, sign_in(), p["notice_version"])
  end

  test "occasion admin can manage only their assigned occasion, never siblings or foreign tenants",
       c do
    admin = sign_in()

    Repo.insert!(%Ep.Occasions.Admin{
      tenant_id: c.tid,
      occasion_id: c.oid,
      identity_id: admin.principal.identity_id
    })

    assert {:ok, _} = Ep.Recruitment.open(admin.principal, c.tid, c.oid, config(), "open")

    assert {:error, :not_found} =
             Ep.Recruitment.manage(admin.principal, c.tid, Ecto.UUID.generate())

    assert {:error, :not_found} =
             Ep.Recruitment.open(sign_in().principal, c.tid, c.oid, config(), "foreign")

    assert {:error, :not_found} =
             Ep.Recruitment.manage(admin.principal, Ecto.UUID.generate(), c.oid)

    Repo.update_all(
      from(a in Ep.Occasions.Admin, where: a.identity_id == ^admin.principal.identity_id),
      set: [status: "revoked"]
    )

    assert {:error, :not_found} =
             Ep.Recruitment.close(
               admin.principal,
               c.tid,
               c.oid,
               %{"reason" => "No authority"},
               "close"
             )
  end

  test "expiry and retirement block new intake even when projected open", c do
    open(c)
    Oban.drain_queue(queue: :projections)
    {:ok, %{config: p}} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)

    Repo.update_all(from(o in Ep.Occasions.Occasion, where: o.id == ^c.oid),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :recruitment_closed} = Ep.Recruitment.landing(c.tid, "sl2030")
    assert {:error, :recruitment_closed} = submit(c, sign_in(), p["notice_version"])

    assert {:ok, _} =
             Ep.Recruitment.close(
               c.owner.principal,
               c.tid,
               c.oid,
               %{"reason" => "Expiry reached"},
               "close"
             )

    assert {:error, :occasion_expired} =
             Ep.Recruitment.open(c.owner.principal, c.tid, c.oid, config(), "new-open")

    Repo.update_all(from(o in Ep.Occasions.Occasion, where: o.id == ^c.oid),
      set: [status: "retired"]
    )

    assert {:error, :not_found} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)
  end

  test "stopped view blocks public read; rollback removes all application acceptance", c do
    open(c)
    Oban.drain_queue(queue: :projections)

    control =
      from(v in Ep.Projections.Control,
        where: v.tenant_id == ^c.tid and v.name == "occasion_directory"
      )

    Repo.update_all(control, set: [state: "stopped"])

    assert {:error, :view_stopped} = Ep.Recruitment.landing(c.tid, "sl2030")
    {:ok, %{config: p}} = Ep.Recruitment.manage(c.owner.principal, c.tid, c.oid)
    prospect = sign_in()

    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _} = submit(c, prospect, p["notice_version"])
               Repo.rollback(:abort)
             end)

    assert Repo.aggregate(Intake, :count) == 0

    assert Repo.aggregate(
             from(e in Ep.Events.Event, where: e.event_type == "RecruitmentApplicationSubmitted"),
             :count
           ) == 0
  end

  test "UUID spelling is canonicalized for scoped events and idempotency", c do
    assert {:ok, first} =
             Ep.Recruitment.open(
               c.owner.principal,
               String.upcase(c.tid),
               String.upcase(c.oid),
               config(),
               "case-key"
             )

    assert {:ok, %{result: result, replayed: true}} =
             Ep.Recruitment.open(c.owner.principal, c.tid, c.oid, config(), "case-key")

    assert result == first.result
  end
end
