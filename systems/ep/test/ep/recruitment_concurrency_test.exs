defmodule Ep.RecruitmentConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Ep.Support.AuthHelpers
  alias Ecto.Adapters.SQL.Sandbox
  alias Ep.Repo

  test "closure and intake serialize at the authoritative occasion row" do
    {owner, recipient, tid, oid, version} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = sign_in()
        recipient = sign_in()

        {:ok, %{result: t}} =
          Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Recruitment race"}, "tenant")

        tid = t["tenant_id"]

        {:ok, %{result: o}} =
          Ep.Occasions.create(
            owner.principal,
            tid,
            %{"name" => "Race", "slug" => "race", "expires_at" => "2032-01-01T00:00:00Z"},
            "occasion"
          )

        oid = o["occasion_id"]

        Ep.Recruitment.open(
          owner.principal,
          tid,
          oid,
          %{
            "title" => "Join us",
            "instructions" => "Review",
            "privacy_notice_url" => "https://example.test/privacy",
            "confirm_manual_review" => true
          },
          "open"
        )

        {:ok, %{config: config}} = Ep.Recruitment.manage(owner.principal, tid, oid)
        {owner, recipient, tid, oid, config["notice_version"]}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> cleanup({owner, recipient, tid, "", oid}) end)
    end)

    supervisor = start_supervised!({Task.Supervisor, []})
    parent = self()
    barrier = make_ref()

    tasks =
      for action <- [:submit, :close] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:ready, self()})

          receive do
            {:go, ^barrier} ->
              Sandbox.unboxed_run(Repo, fn ->
                case action do
                  :close ->
                    Ep.Recruitment.close(
                      owner.principal,
                      tid,
                      oid,
                      %{"reason" => "Close in race"},
                      "close"
                    )

                  :submit ->
                    Ep.Recruitment.submit(
                      recipient.principal,
                      tid,
                      oid,
                      %{"notice_version" => version, "acknowledge_notice" => true},
                      "submit"
                    )
                end
              end)
          end
        end)
      end

    Enum.each(tasks, fn t -> assert_receive {:ready, pid} when pid == t.pid end)
    Enum.each(tasks, fn t -> send(t.pid, {:go, barrier}) end)
    [submitted, closed] = Task.await_many(tasks, 15_000)
    assert match?({:ok, _}, closed)
    assert match?({:ok, _}, submitted) || submitted == {:error, :recruitment_closed}

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.get!(Ep.Occasions.Occasion, oid).recruitment_state == "closed"

      assert {:error, :recruitment_closed} =
               Ep.Recruitment.submit(
                 recipient.principal,
                 tid,
                 oid,
                 %{"notice_version" => version, "acknowledge_notice" => true},
                 "after-close"
               )

      events =
        Repo.all(
          from(e in Ep.Events.Event, where: e.occasion_id == ^oid, order_by: e.stream_version)
        )

      if match?({:ok, _}, submitted) do
        accepted = Enum.find(events, &(&1.event_type == "RecruitmentApplicationSubmitted"))
        closed = Enum.find(events, &(&1.event_type == "OccasionRecruitmentClosed"))
        assert accepted.stream_version < closed.stream_version
      end
    end)
  end

  defp cleanup({owner, recipient, tid, iid, oid}) do
    ids = [owner.principal.identity_id, recipient.principal.identity_id]
    identities = Repo.all(from(i in Ep.Auth.Identity, where: i.id in ^ids))
    party_ids = Enum.map(identities, & &1.party_id)
    emails = Enum.map(identities, & &1.email)

    event_ids =
      Repo.all(from(e in Ep.Events.Event, where: e.actor_identity_id in ^ids, select: e.id))

    Repo.transaction(fn ->
      Repo.delete_all(
        from(j in Oban.Job,
          where:
            fragment("?->>'tenant_id'", j.args) == ^tid or
              fragment("?->>'invitation_id'", j.args) == ^iid
        )
      )

      Repo.delete_all(from(v in Ep.Occasions.Directory, where: v.tenant_id == ^tid))
      Repo.delete_all(from(v in Ep.Projections.TenantDirectory, where: v.tenant_id == ^tid))
      Repo.delete_all(from(i in Ep.Projections.Inbox, where: i.tenant_id == ^tid))
      Repo.delete_all(from(o in Ep.Events.Outbox, where: o.tenant_id == ^tid))
      Repo.delete_all(from(d in Ep.Events.Details, where: d.event_id in ^event_ids))
      Repo.delete_all(from(e in Ep.Events.Event, where: e.id in ^event_ids))

      Repo.delete_all(
        from(h in Ep.Events.StreamHead,
          where:
            h.stream_id == ^tid or h.stream_id in ^ids or
              h.scope_key == ^("tenant:" <> tid <> ":occasion:" <> (oid || ""))
        )
      )

      Repo.delete_all(from(a in Ep.Recruitment.Application, where: a.tenant_id == ^tid))
      Repo.delete_all(from(i in Ep.Invitations.Invitation, where: i.tenant_id == ^tid))
      Repo.delete_all(from(a in Ep.Occasions.Admin, where: a.tenant_id == ^tid))
      Repo.delete_all(from(o in Ep.Occasions.Occasion, where: o.tenant_id == ^tid))
      Repo.delete_all(from(a in Ep.Tenancy.Access, where: a.tenant_id == ^tid))
      Repo.delete_all(from(c in Ep.Projections.Control, where: c.tenant_id == ^tid))
      Repo.delete_all(from(c in Ep.Events.CommandReceipt, where: c.identity_id in ^ids))
      Repo.delete_all(from(t in Ep.Tenancy.Tenant, where: t.id == ^tid))
      Repo.delete_all(from(s in Ep.Auth.Session, where: s.identity_id in ^ids))
      Repo.delete_all(from(i in Ep.Auth.Identity, where: i.id in ^ids))
      Repo.delete_all(from(p in Ep.Auth.Party, where: p.id in ^party_ids))
      Repo.delete_all(from(m in Ep.Auth.MagicLink, where: m.email in ^emails))
    end)
  end
end
