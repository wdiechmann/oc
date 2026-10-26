defmodule EpWeb.RequestPipeline do
  @moduledoc "Request processing inside the unexpected-error boundary, including development reload failures."
  use Plug.Builder

  if Application.compile_env(:ep, [EpWeb.Endpoint, :code_reloader], false) do
    plug Phoenix.CodeReloader
  end

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug EpWeb.Router
end
