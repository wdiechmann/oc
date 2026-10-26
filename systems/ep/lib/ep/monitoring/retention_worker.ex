defmodule Ep.Monitoring.RetentionWorker do
  @moduledoc "Bounded cleanup independent of stopped ordinary monitoring projections."
  use Oban.Worker, queue: :monitoring, max_attempts: 5
  @impl Oban.Worker
  def perform(_) do
    Ep.Monitoring.Privacy.retain()
    :ok
  end
end
