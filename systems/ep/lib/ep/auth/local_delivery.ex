defmodule Ep.Auth.LocalDelivery do
  @moduledoc "Private development-only mailbox. Never exposed over HTTP or enabled in production."
  def deliver(email, token) do
    if Application.get_env(:ep, :local_magic_links_enabled, false) do
      dir = Application.fetch_env!(:ep, :magic_link_spool_dir)

      with :ok <- File.mkdir_p(dir),
           :ok <- File.chmod(dir, 0o700) do
        path = Path.join(dir, Ecto.UUID.generate() <> ".json")
        # The parent directory is private before any credential file is created.
        with :ok <- File.write(path, Jason.encode!(%{email: email, token: token}), [:exclusive]),
             :ok <- File.chmod(path, 0o600),
             do: :ok
      end
    else
      {:error, :delivery_unavailable}
    end
  end
end
