defmodule Ep.Monitoring.Worker do
  @moduledoc false
  use Oban.Worker, queue: :monitoring, max_attempts: 10
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"issue_id" => id}}) do
    case Ep.Monitoring.Projector.deliver(id) do
      {:ok, _} -> :ok
      {:error, :view_stopped} -> {:snooze, 60}
      {:error, reason} -> {:error, reason}
    end
  end
end
