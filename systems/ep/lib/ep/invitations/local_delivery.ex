defmodule Ep.Invitations.LocalDelivery do
  @moduledoc "Development-only private invitation mailbox; invitation IDs confer no authority."
  def deliver(message) do
    if Application.get_env(:ep, :local_magic_links_enabled, false) do
      dir = Application.fetch_env!(:ep, :invitation_spool_dir)

      with :ok <- File.mkdir_p(dir), :ok <- File.chmod(dir, 0o700) do
        path = Path.join(dir, message.invitation_id <> ".json")

        with :ok <- File.write(path, Jason.encode!(message)),
             :ok <- File.chmod(path, 0o600),
             do: :ok
      end
    else
      {:error, :delivery_unavailable}
    end
  end
end
