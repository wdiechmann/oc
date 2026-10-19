defmodule Mix.Tasks.Ep.Outbox.Recover do
  use Mix.Task
  @shortdoc "Requeue up to 100 tenants with pending EP outbox deliveries"
  @moduledoc """
  Starts the application and enqueues local projection work for committed pending outbox rows.
  Safe to repeat: the consumer inbox prevents duplicate application of the same event.
  Stopped MVs remain stopped. This does not erase data, send email or invoke vendor actions.
  """
  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.start")
    {:ok, count} = Ep.Outbox.requeue_pending()
    Mix.shell().info("Queued #{count} tenant projection recoveries")
  end
end
