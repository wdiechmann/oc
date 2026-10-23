defmodule Ep.AuthTest do
  use Ep.DataCase, async: true
  alias Ep.Auth.{Identity, MagicLink, Session}
  alias Ep.Events.{Details, Event}
  import Ep.Support.AuthHelpers

  test "verification is one-use and stores hashes rather than credentials" do
    assert {:ok, %{delivery: %{token: link_token}}} =
             Ep.Auth.request_magic_link("first@example.test")

    assert {:ok, result} = Ep.Auth.verify_magic_link(link_token)
    assert {:ok, principal} = Ep.Auth.authenticate(result.token)
    assert principal == result.principal
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(link_token)
    assert Repo.one(MagicLink).token_hash != link_token
    assert Repo.one(Session).token_hash != result.token
    assert Repo.one(Identity).verified_at
    details = Repo.one(Details).payload
    refute Map.has_key?(details, "email")
    refute Map.has_key?(details, "token")
    assert Repo.one(Event).event_type == "IdentityEstablished"
  end

  test "expired links are rejected without creating an identity" do
    {:ok, %{delivery: %{token: token}}} = Ep.Auth.request_magic_link("expired@example.test")
    Repo.update_all(MagicLink, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(token)
    assert Repo.aggregate(Identity, :count) == 0
  end

  test "resend invalidates prior link and fourth request is silently throttled" do
    tokens =
      Enum.map(1..3, fn _ ->
        assert {:ok, %{delivery: %{token: token}}} =
                 Ep.Auth.request_magic_link("limit@example.test")

        token
      end)

    [first, second, third] = tokens
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(first)
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(second)
    assert {:ok, %{delivery: nil}} = Ep.Auth.request_magic_link("limit@example.test")
    assert Repo.aggregate(MagicLink, :count) == 3
    assert {:ok, _} = Ep.Auth.verify_magic_link(third)
  end

  test "subsequent sign-in preserves canonical identity" do
    a = sign_in("same@example.test")
    b = sign_in("same@example.test")
    assert a.principal.identity_id == b.principal.identity_id
    assert a.token != b.token
    assert Repo.aggregate(Identity, :count) == 1
  end

  test "revoked, expired and suspended sessions fail current checks" do
    signed = sign_in()
    session = Repo.get!(Session, signed.principal.session_id)
    Repo.update!(Ecto.Changeset.change(session, revoked_at: DateTime.utc_now()))
    assert {:error, :unauthenticated} = Ep.Auth.authenticate(signed.token)

    assert {:error, :unauthenticated} =
             Ep.Tenancy.create_tenant(signed.principal, %{"name" => "No"}, "revoked")

    another = sign_in()

    Repo.update_all(from(s in Session, where: s.id == ^another.principal.session_id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert {:error, :unauthenticated} = Ep.Auth.authenticate(another.token)

    active = sign_in()

    Repo.update_all(from(i in Identity, where: i.id == ^active.principal.identity_id),
      set: [status: "suspended"]
    )

    assert {:error, :unauthenticated} = Ep.Auth.authenticate(active.token)
  end

  test "malformed identity input and credential are rejected" do
    assert {:error, :invalid_email} = Ep.Auth.request_magic_link(nil)
    assert {:error, :invalid_email} = Ep.Auth.request_magic_link("not-email")
    assert {:error, :invalid_token} = Ep.Auth.verify_magic_link(%{})
    assert {:error, :unauthenticated} = Ep.Auth.authenticate("forged")
  end
end
