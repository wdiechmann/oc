defmodule Ep.InvitationConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Ep.Support.AuthHelpers
  alias Ecto.Adapters.SQL.Sandbox
  alias Ep.Repo

  for scope <- [:tenant, :occasion] do
    @scope scope
    test "racing #{@scope} acceptance and revocation on separate connections have one winner" do
      scope = @scope

      fixture =
        Sandbox.unboxed_run(Repo, fn ->
          owner = sign_in()
          recipient = sign_in()
          email = Repo.get!(Ep.Auth.Identity, recipient.principal.identity_id).email

          {:ok, %{result: t}} =
            Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Invitation race"}, "tenant")

          oid = occasion_id(scope, owner, t["tenant_id"])

          {:ok, %{result: i}} =
            Ep.Invitations.invite(
              owner.principal,
              t["tenant_id"],
              %{"email" => email},
              "invite",
              oid
            )

          {owner, recipient, t["tenant_id"], i["invitation_id"], oid}
        end)

      {owner, recipient, tid, iid, oid} = fixture
      on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup(fixture) end) end)
      supervisor = start_supervised!({Task.Supervisor, []})
      parent = self()
      barrier = make_ref()

      tasks =
        for action <- [:accept, :revoke] do
          Task.Supervisor.async_nolink(supervisor, fn ->
            send(parent, {:ready, self()})

            receive do
              {:go, ^barrier} ->
                Sandbox.unboxed_run(Repo, fn ->
                  case action do
                    :accept -> Ep.Invitations.accept(recipient.principal, tid, iid, "accept", oid)
                    :revoke -> Ep.Invitations.revoke(owner.principal, tid, iid, "revoke", oid)
                  end
                end)
            end
          end)
        end

      Enum.each(tasks, fn task -> assert_receive {:ready, pid} when pid == task.pid end)
      Enum.each(tasks, fn task -> send(task.pid, {:go, barrier}) end)
      results = Task.await_many(tasks, 15_000)
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :invitation_unavailable}, &1)) == 1

      Sandbox.unboxed_run(Repo, fn ->
        invitation = Repo.get!(Ep.Invitations.Invitation, iid)

        access =
          if oid,
            do:
              Repo.get_by(Ep.Occasions.Admin,
                tenant_id: tid,
                occasion_id: oid,
                identity_id: recipient.principal.identity_id
              ),
            else:
              Repo.get_by(Ep.Tenancy.Access,
                tenant_id: tid,
                identity_id: recipient.principal.identity_id
              )

        if oid,
          do:
            refute(
              Repo.get_by(Ep.Tenancy.Access,
                tenant_id: tid,
                identity_id: recipient.principal.identity_id
              )
            )

        assert (invitation.status == "accepted" && access && access.status == "active") ||
                 (invitation.status == "revoked" && is_nil(access))
      end)
    end
  end

  defp occasion_id(:tenant, _, _), do: nil

  defp occasion_id(:occasion, owner, tenant_id) do
    {:ok, %{result: occasion}} =
      Ep.Occasions.create(
        owner.principal,
        tenant_id,
        %{"name" => "Race", "slug" => "race", "expires_at" => "2032-01-01T00:00:00Z"},
        "occasion"
      )

    occasion["occasion_id"]
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
