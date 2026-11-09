defmodule Ep.Finance.BookOverview do
  @moduledoc "Read-only posted fiscal overview. Called only inside Books.get's authorized transaction."
  import Ecto.Query
  alias Ep.Repo
  alias Ep.Finance.{Book, SetupState, SetupView, Setup, ReportPresets}
  alias Ep.Events.{Event, Details}
  alias Ep.Projections.Control

  def read_authorized!(book, cutoff \\ nil) do
    tid = book.tenant_id
    state = Repo.get(SetupState, book.id)
    view = Repo.get_by(SetupView, tenant_id: tid, book_id: book.id)

    control =
      Repo.one(
        from c in Control,
          where: c.tenant_id == ^tid and c.name == "finance_setup",
          lock: "FOR SHARE"
      )

    cond do
      book.accounting_authority != "ep" ->
        %{status: "external"}

      (control && control.state != "running") ||
          (is_nil(control) && Repo.exists?(from s in SetupState, where: s.tenant_id == ^tid)) ->
        %{status: "unavailable"}

      if(state, do: state.version, else: 0) != if(view, do: view.source_version, else: 0) ->
        %{status: "pending"}

      true ->
        cutoff =
          cutoff ||
            Repo.one(
              from b in Book,
                where: b.id == ^book.id,
                select: type(fragment("timezone(?, now())::date", b.timezone), :date)
            )

        data = if view, do: view.data, else: %{}

        accounts =
          Setup.normalize_accounts(data["accounts"] || [])
          |> Enum.filter(&(&1["kind"] == "posting"))

        definition =
          ReportPresets.profit_loss(
            accounts,
            data["catalogue_entries"] || [],
            if(view, do: view.source_version, else: 0)
          )

        facts =
          Repo.all(
            from e in Event,
              join: d in Details,
              on: d.event_id == e.id,
              where:
                e.tenant_id == ^tid and e.stream_id == ^book.id and
                  e.stream_type == "finance_journals" and e.event_type == "JournalPosted",
              select: d.payload
          )

        calculate(definition, facts, cutoff, book.fiscal_year_start_month, book.base_currency)
    end
  end

  def calculate(preset, facts, cutoff, fiscal_month, currency) do
    start =
      Date.new!(cutoff.year - if(cutoff.month < fiscal_month, do: 1, else: 0), fiscal_month, 1)

    prior_start = Date.new!(start.year - 1, fiscal_month, 1)
    prior_month = Date.new!(cutoff.year - 1, cutoff.month, 1)

    prior_cutoff =
      Date.new!(
        prior_month.year,
        prior_month.month,
        min(cutoff.day, Date.days_in_month(prior_month))
      )

    [income, expenses | _] = preset["definition"]["lines"]
    income_ids = MapSet.new(income["account_ids"])
    expense_ids = MapSet.new(expenses["account_ids"])

    months =
      for offset <- 0..11 do
        month = month_start(start, offset)

        %{
          month: Date.to_iso8601(month),
          income_minor: 0,
          expenses_minor: 0,
          future: Date.compare(month, cutoff) == :gt
        }
      end

    {months, previous, count} =
      Enum.reduce(facts, {months, %{income_minor: 0, expenses_minor: 0}, 0}, fn fact,
                                                                                {months, previous,
                                                                                 count} ->
        date = Date.from_iso8601!(fact["draft"]["data"]["posting_date"])

        values =
          Enum.reduce(fact["posting"]["accounts"], %{income_minor: 0, expenses_minor: 0}, fn row,
                                                                                             values ->
            id = row["account"]["id"]

            values
            |> Map.update!(
              :income_minor,
              &(&1 - if(MapSet.member?(income_ids, id), do: row["post_minor"], else: 0))
            )
            |> Map.update!(
              :expenses_minor,
              &(&1 + if(MapSet.member?(expense_ids, id), do: row["post_minor"], else: 0))
            )
          end)

        cond do
          Date.compare(date, start) != :lt && Date.compare(date, cutoff) != :gt ->
            index = (date.year - start.year) * 12 + date.month - start.month

            months =
              List.update_at(months, index, fn month ->
                Map.merge(month, values, fn _, a, b -> a + b end)
              end)

            {months, previous, count + 1}

          Date.compare(date, prior_start) != :lt && Date.compare(date, prior_cutoff) != :gt ->
            {months, Map.merge(previous, values, fn _, a, b -> a + b end), count}

          true ->
            {months, previous, count}
        end
      end)

    totals =
      %{
        income_minor: Enum.sum(Enum.map(months, & &1.income_minor)),
        expenses_minor: Enum.sum(Enum.map(months, & &1.expenses_minor))
      }
      |> profit()

    previous = profit(previous)

    changes =
      Map.new(~w(income_minor expenses_minor profit_minor)a, fn key ->
        prior = previous[key]
        {key, if(prior > 0, do: div((totals[key] - prior) * 10000, prior), else: nil)}
      end)

    %{
      status: "ready",
      start_date: Date.to_iso8601(start),
      as_of: Date.to_iso8601(cutoff),
      prior_as_of: Date.to_iso8601(prior_cutoff),
      currency: currency,
      months: months,
      totals: totals,
      previous: previous,
      change_bps: changes,
      journal_count: count,
      classification_warnings: preset["classification_warnings"] || []
    }
  end

  defp profit(values),
    do: Map.put(values, :profit_minor, values.income_minor - values.expenses_minor)

  defp month_start(start, offset) do
    serial = start.year * 12 + start.month - 1 + offset
    Date.new!(div(serial, 12), rem(serial, 12) + 1, 1)
  end
end
