defmodule Ep.Auth do
  @moduledoc "Email magic-link signup and revocable, opaque API sessions."
  import Ecto.Query
  alias Ep.Auth.{Identity, MagicLink, Party, Principal, Session}
  alias Ep.{Events, Repo}

  def request_magic_link(email, backend_id \\ "internal") do
    issue_magic_link(email, backend_id, false)
  end

  def request_sign_in_link(email, backend_id), do: issue_magic_link(email, backend_id, true)

  defp issue_magic_link(email, backend_id, existing_only) do
    with {:ok, email} <- normalize_email(email) do
      token = new_token()
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        Events.lock!("email:" <> email)
        recent = DateTime.add(now, -900, :second)

        count =
          Repo.aggregate(
            from(m in MagicLink, where: m.email == ^email and m.inserted_at > ^recent),
            :count
          )

        identity =
          if existing_only,
            do:
              Repo.one(
                from i in Identity,
                  where: i.email == ^email and i.status == "active" and not is_nil(i.verified_at)
              )

        if count < 3 && (!existing_only || identity) do
          pending =
            from(m in MagicLink,
              where: m.email == ^email and m.backend_id == ^backend_id and is_nil(m.consumed_at)
            )

          Repo.update_all(pending, set: [consumed_at: now])

          expires_at = DateTime.add(now, 900, :second)

          Repo.insert!(%MagicLink{
            email: email,
            backend_id: backend_id,
            existing_identity_id: identity && identity.id,
            token_hash: hash(token),
            expires_at: expires_at
          })

          %{
            status: "check_your_email",
            delivery: %{email: email, token: token, expires_at: expires_at}
          }
        else
          %{status: "check_your_email", delivery: nil}
        end
      end)
    end
  end

  def verify_magic_link(token, backend_id \\ "internal")

  def verify_magic_link(token, backend_id)
      when is_binary(token) and byte_size(token) in 32..128 do
    token_hash = hash(token)
    session_token = new_token()

    Repo.transaction(fn ->
      candidate =
        Repo.get_by(MagicLink, token_hash: token_hash, backend_id: backend_id) ||
          Repo.rollback(:invalid_token)

      Events.lock!("email:" <> candidate.email)
      link = Repo.one!(from(m in MagicLink, where: m.id == ^candidate.id, lock: "FOR UPDATE"))
      now = DateTime.utc_now()

      unless is_nil(link.consumed_at) and DateTime.compare(link.expires_at, now) == :gt do
        Repo.rollback(:invalid_token)
      end

      identity =
        if link.existing_identity_id do
          Repo.one(
            from i in Identity,
              where:
                i.id == ^link.existing_identity_id and i.email == ^link.email and
                  i.status == "active" and not is_nil(i.verified_at),
              lock: "FOR SHARE"
          ) || Repo.rollback(:invalid_token)
        else
          get_or_establish_identity!(link.email, now)
        end

      unless identity.status == "active", do: Repo.rollback(:invalid_token)
      Repo.update!(Ecto.Changeset.change(link, consumed_at: now))

      expires_at =
        DateTime.add(now, Application.get_env(:ep, :session_lifetime_seconds, 43_200), :second)

      session =
        Repo.insert!(%Session{
          identity_id: identity.id,
          token_hash: hash(session_token),
          expires_at: expires_at
        })

      %{
        token: session_token,
        expires_at: expires_at,
        principal: %Principal{identity_id: identity.id, session_id: session.id}
      }
    end)
  end

  def verify_magic_link(_, _), do: {:error, :invalid_token}

  def authenticate(token) when is_binary(token) and byte_size(token) in 32..128 do
    query = session_query(hash(token), DateTime.utc_now())

    case Repo.one(query) do
      {session, identity} -> {:ok, %Principal{identity_id: identity.id, session_id: session.id}}
      nil -> {:error, :unauthenticated}
    end
  end

  def authenticate(_), do: {:error, :unauthenticated}

  def lock_principal!(%Principal{} = principal) do
    now = DateTime.utc_now()

    query =
      from(s in Session,
        join: i in Identity,
        on: i.id == s.identity_id,
        where:
          s.id == ^principal.session_id and i.id == ^principal.identity_id and
            is_nil(s.revoked_at) and s.expires_at > ^now and i.status == "active",
        lock: "FOR SHARE",
        select: i
      )

    Repo.one(query) || Repo.rollback(:unauthenticated)
  end

  def revoke_session(%Principal{} = principal) do
    query =
      from s in Session,
        where:
          s.id == ^principal.session_id and s.identity_id == ^principal.identity_id and
            is_nil(s.revoked_at)

    Repo.update_all(query, set: [revoked_at: DateTime.utc_now()])
    :ok
  end

  defp session_query(token_hash, now) do
    from(s in Session,
      join: i in Identity,
      on: i.id == s.identity_id,
      where:
        s.token_hash == ^token_hash and is_nil(s.revoked_at) and s.expires_at > ^now and
          i.status == "active",
      select: {s, i}
    )
  end

  defp get_or_establish_identity!(email, now) do
    case Repo.get_by(Identity, email: email) do
      nil ->
        party = Repo.insert!(%Party{})
        identity = Repo.insert!(%Identity{party_id: party.id, email: email, verified_at: now})
        command_id = Ecto.UUID.generate()

        Events.append!(
          %{
            scope: "global",
            scope_key: "global",
            stream_type: "identity",
            stream_id: identity.id,
            actor_identity_id: identity.id,
            command_id: command_id,
            correlation_id: command_id
          },
          [
            {"IdentityEstablished",
             %{"party_id" => party.id, "verification_method" => "email_magic_link"}}
          ]
        )

        identity

      identity ->
        identity
    end
  end

  defp normalize_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if byte_size(email) <= 254 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u, email),
      do: {:ok, email},
      else: {:error, :invalid_email}
  end

  defp normalize_email(_), do: {:error, :invalid_email}
  defp new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp hash(token), do: :crypto.hash(:sha256, token)
end
