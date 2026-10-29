defmodule Ep.Finance.BookProjector do
  @moduledoc "Ordered, transactional book-context projection. Replays never execute financial work."
  import Ecto.Query
  alias Ep.{Repo, Events}
  alias Ep.Events.{Event, Details, Outbox}
  alias Ep.Projections.Inbox
  alias Ep.Finance.{BookView, Books, BookWorker}
  @consumer "finance_books:v1"
  def deliver(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-books:" <> tid)
      Books.running!(tid)

      rows =
        Repo.all(
          from o in Outbox,
            join: e in Event,
            on: e.id == o.event_id,
            where:
              o.tenant_id == ^tid and is_nil(o.delivered_at) and e.stream_type == "finance_books",
            order_by: e.stream_version,
            limit: 1000,
            select: {o, e}
        )

      Enum.each(rows, fn {out, event} ->
        consume!(tid, event)

        Repo.update!(Ecto.Changeset.change(out, delivered_at: DateTime.utc_now()))
      end)

      if length(rows) == 1000, do: Oban.insert!(BookWorker.new(%{tenant_id: tid}))
      length(rows)
    end)
  end

  @doc "Trusted operator-only book-metadata rebuild; no dispatch, append or money movement."
  def rebuild(tid) do
    Repo.transaction(fn ->
      Events.lock!("projection:finance-books:" <> tid)
      Repo.delete_all(from v in BookView, where: v.tenant_id == ^tid)
      Repo.delete_all(from i in Inbox, where: i.tenant_id == ^tid and i.consumer == ^@consumer)

      Repo.all(
        from e in Event,
          where: e.tenant_id == ^tid and e.stream_type == "finance_books",
          order_by: e.stream_version
      )
      |> Enum.each(&consume!(tid, &1))

      :ok
    end)
  end

  defp consume!(tid, event) do
    unless Repo.get_by(Inbox, consumer: @consumer, event_id: event.id) do
      checkpoint =
        Repo.aggregate(from(v in BookView, where: v.tenant_id == ^tid), :max, :source_version) ||
          0

      valid =
        event.schema_version == 1 && event.tenant_id == tid && event.stream_id == tid &&
          event.scope == "tenant" && event.scope_key == "tenant:" <> tid &&
          is_nil(event.occasion_id) &&
          event.event_type in ["BookCreated", "BookRevised"] &&
          event.stream_version == checkpoint + 1

      unless valid do
        Repo.rollback(:projection_gap)
      end

      data = Repo.get!(Details, event.id).payload |> Map.fetch!("book")
      unless data["tenant_id"] == tid, do: Repo.rollback(:projection_scope)

      attrs = %{
        book_id: data["book_id"],
        tenant_id: tid,
        data: data,
        source_version: event.stream_version
      }

      case Repo.get(BookView, data["book_id"]) do
        nil -> Repo.insert!(struct!(BookView, attrs))
        row -> Repo.update!(Ecto.Changeset.change(row, attrs))
      end

      Repo.insert!(%Inbox{consumer: @consumer, event_id: event.id, tenant_id: tid})
    end
  end
end
