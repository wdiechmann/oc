defmodule Ep.Outbox do
  @moduledoc "Operational recovery of committed local deliveries, independent of a global watermark."
  import Ecto.Query
  alias Ep.{Repo, Events.Outbox}

  def requeue_pending(limit \\ 100) when is_integer(limit) and limit in 1..1000 do
    tenant_ids =
      Repo.all(
        from(o in Outbox,
          where: is_nil(o.delivered_at),
          distinct: o.tenant_id,
          order_by: o.tenant_id,
          limit: ^limit,
          select: o.tenant_id
        )
      )

    Repo.transaction(fn ->
      Enum.each(tenant_ids, fn id ->
        types =
          Repo.all(
            from(o in Outbox,
              join: e in Ep.Events.Event,
              on: e.id == o.event_id,
              where: o.tenant_id == ^id and is_nil(o.delivered_at),
              distinct: e.stream_type,
              select: e.stream_type
            )
          )

        if "finance_setup" in types,
          do: Oban.insert!(Ep.Finance.SetupWorker.new(%{tenant_id: id}))

        if "finance_books" in types, do: Oban.insert!(Ep.Finance.BookWorker.new(%{tenant_id: id}))

        if "tenant" in types, do: Oban.insert!(Ep.Projections.TenantWorker.new(%{tenant_id: id}))

        if "occasion" in types,
          do: Oban.insert!(Ep.Projections.OccasionWorker.new(%{tenant_id: id}))
      end)

      length(tenant_ids)
    end)
  end
end
