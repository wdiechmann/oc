defmodule Mix.Tasks.Ep.Monitoring.Recover do
  @shortdoc "Requeue pending monitoring facts without repeating external effects"
  use Mix.Task
  @impl Mix.Task
  def run(_) do
    Mix.Task.run("app.start")
    Mix.shell().info("Scheduled #{Ep.Monitoring.Projector.recover()} issue streams")
  end
end
