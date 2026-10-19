defmodule Ep.Invitations.DeliveryWorker do
  @moduledoc "Durable notification wakeup for tenant and occasion invitations; IDs are not credentials."
  use Oban.Worker, queue: :default, max_attempts: 10
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => id}}) do
    case Ep.Invitations.notification(id) do
      :skip ->
        :ok

      {:ok, message} ->
        case Application.get_env(:ep, :invitation_delivery) do
          nil -> {:error, :delivery_unavailable}
          adapter -> adapter.deliver(message)
        end
    end
  end
end
