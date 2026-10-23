defmodule Ep.Support.AuthHelpers do
  import ExUnit.Assertions

  def sign_in(email \\ "user-#{System.unique_integer([:positive])}@example.test") do
    assert {:ok, %{delivery: %{token: token}}} = Ep.Auth.request_magic_link(email)
    assert {:ok, session} = Ep.Auth.verify_magic_link(token)
    session
  end
end
