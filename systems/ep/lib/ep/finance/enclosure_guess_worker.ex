defmodule Ep.Finance.EnclosureGuessWorker do
  use Oban.Worker,
    queue: :projections,
    max_attempts: 5,
    unique: [
      period: 60,
      keys: [:tenant_id, :book_id, :after_id],
      states: [:available, :scheduled, :retryable]
    ]

  import Ecto.Query
  @impl true
  def perform(%Oban.Job{args: %{"tenant_id" => tid, "book_id" => bid} = args}) do
    case Ep.Finance.EnclosureLearning.recalculate(tid, bid, args["after_id"]) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) when args == %{} do
    Ep.Repo.all(
      from r in Ep.Finance.EnclosureLearningRecord,
        where: not is_nil(r.attachment_id),
        distinct: [r.tenant_id, r.book_id],
        select: {r.tenant_id, r.book_id}
    )
    |> Enum.each(fn {tid, bid} -> Ep.Finance.EnclosureLearning.enqueue!(tid, bid) end)

    :ok
  end
end
