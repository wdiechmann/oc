defmodule Ep.Finance.EnclosureLearning do
  @moduledoc "Protected document interpretation support; confirmed row choices are learning evidence."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Finance.{EnclosureLearningRecord, EnclosureGuess, JournalWork, JournalRows, Setup}
  @keys ~w(supplier total vat net date due_date invoice_number vat_number currency)

  def extract(principal, tid, bid, row_id, upload_id, p, app) do
    with {:ok, tid} <- Ecto.UUID.cast(tid),
         {:ok, bid} <- Ecto.UUID.cast(bid),
         {:ok, row_id} <- Ecto.UUID.cast(row_id),
         {:ok, upload_id} <- Ecto.UUID.cast(upload_id) do
      extract_scoped(principal, tid, bid, row_id, upload_id, p, app)
    else
      _ -> {:error, :not_found}
    end
  end

  defp extract_scoped(principal, tid, bid, row_id, upload_id, p, app) do
    Repo.transaction(fn ->
      unless Enum.all?([tid, bid, row_id, upload_id], &match?({:ok, _}, Ecto.UUID.cast(&1))),
        do: Repo.rollback(:not_found)

      {_, _, steward} = Setup.authorize!(principal, tid, bid)
      unless steward, do: Repo.rollback(:not_found)
      file = unwrap!(JournalWork.staged_preview(principal, tid, bid, row_id, upload_id, app))

      unless is_map(p) && Enum.sort(Map.keys(p)) == ~w(fields method text) &&
               is_binary(p["text"]) && String.length(p["text"]) in 1..40000 &&
               p["method"] in ~w(ocr pdf_text) &&
               is_list(p["fields"]) && length(p["fields"]) <= 30 &&
               Enum.all?(p["fields"], &valid_field?/1),
             do: Repo.rollback(:invalid_extraction)

      Events.lock!("enclosure-learning:" <> bid)

      digest =
        :crypto.hash(:sha256, :erlang.term_to_binary({file["sha256"], p}))
        |> Base.encode16(case: :lower)

      record =
        Repo.get_by(EnclosureLearningRecord, upload_id: upload_id, extraction_digest: digest) ||
          %EnclosureLearningRecord{
            id: Ecto.UUID.generate(),
            tenant_id: tid,
            book_id: bid,
            row_id: row_id,
            upload_id: upload_id,
            actor_identity_id: principal.identity_id,
            application_id: app,
            document_sha256: file["sha256"],
            extraction_digest: digest,
            supplier_key: EnclosureGuess.supplier(p["fields"]),
            extracted_text: p["text"],
            extracted_fields: %{"fields" => p["fields"], "method" => p["method"]}
          }

      record =
        if Ecto.get_meta(record, :state) == :built do
          guess = EnclosureGuess.calculate(record)

          Repo.insert!(Ecto.Changeset.change(record, initial_guess: guess, best_guess: guess),
            log: false
          )
        else
          record
        end

      %{extraction_id: record.id, best_guess: record.best_guess}
    end)
  end

  def bind!(id, upload, attachment, principal, app, data, original_row) do
    record =
      case Ecto.UUID.cast(id) do
        {:ok, uuid} ->
          Repo.get_by(EnclosureLearningRecord,
            id: uuid,
            tenant_id: upload.tenant_id,
            book_id: upload.book_id,
            row_id: original_row.id,
            upload_id: upload.id,
            actor_identity_id: principal.identity_id,
            application_id: app
          )

        _ ->
          nil
      end

    unless record && is_nil(record.attachment_id) &&
             record.document_sha256 == upload.data["sha256"],
           do: Repo.rollback(:invalid_extraction)

    Events.lock!("enclosure-learning:" <> upload.book_id)
    guess = EnclosureGuess.calculate(record)

    existing = original_row.data

    seeded =
      !existing["void"] && is_nil(existing["debit_account_id"]) &&
        is_nil(existing["credit_account_id"]) &&
        existing["amount_minor"] in [nil, 0] && existing["credit_amount_minor"] in [nil, 0] &&
        existing["credit_total_minor"] in [nil, 0]

    Repo.update!(
      Ecto.Changeset.change(record,
        attachment_id: attachment.id,
        best_guess: guess,
        applied_guess: guess,
        seeded: seeded,
        guess_version: record.guess_version + 1
      ),
      log: false
    )

    data =
      if seeded do
        patch = guess["row"] |> Map.update!("amount_minor", &(&1 || 0))

        Map.update!(data, "rows", fn rows ->
          Enum.map(rows, fn row ->
            if row["id"] == original_row.id do
              patch =
                if String.trim(row["reference"] || "") != "",
                  do: Map.put(patch, "reference", row["reference"]),
                  else: patch

              Map.merge(row, patch)
            else
              row
            end
          end)
        end)
      else
        data
      end

    enqueue!(upload.tenant_id, upload.book_id)
    data
  end

  # Called with the same transaction as journal acceptance, including non-row workflows.
  def sync!(draft, event_id) do
    Events.lock!("enclosure-learning:" <> draft.book_id)
    rows = Map.new(draft.data["rows"] || [], &{&1["id"], &1})
    ids = Map.keys(rows)

    records =
      Repo.all(
        from r in EnclosureLearningRecord,
          where:
            r.tenant_id == ^draft.tenant_id and r.book_id == ^draft.book_id and r.row_id in ^ids and
              not is_nil(r.attachment_id)
      )

    Enum.each(records, fn record ->
      if row = rows[record.row_id] do
        preview =
          Enum.find(
            get_in(draft.validation, ["posting_preview", "rows"]) || [],
            &(&1["row_id"] == row["id"])
          )

        values =
          JournalRows.input(row)
          |> Map.merge(Map.take(row, ~w(credit_total_minor posting_debit_minor)))
          |> Map.put("posting_legs", if(preview, do: preview["legs"], else: []))
          |> Map.put("posting_date", draft.data["posting_date"])

        if values != record.used_values do
          Repo.update!(
            Ecto.Changeset.change(record,
              used_values: values,
              used_event_id: event_id,
              used_confirmed_at: nil
            ),
            log: false
          )
        end
      end
    end)
  end

  def confirm!(tid, bid, row_id, event_id) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(r in EnclosureLearningRecord,
          where:
            r.tenant_id == ^tid and r.book_id == ^bid and r.row_id == ^row_id and
              not is_nil(r.attachment_id)
        ),
        set: [used_confirmed_at: now, used_event_id: event_id, updated_at: now]
      )

    if count > 0, do: enqueue!(tid, bid)
  end

  def confirm_posted!(draft, event_id) do
    sync!(draft, event_id)
    ids = Enum.map(draft.data["rows"] || [], & &1["id"])
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(r in EnclosureLearningRecord,
          where:
            r.tenant_id == ^draft.tenant_id and r.book_id == ^draft.book_id and r.row_id in ^ids and
              not is_nil(r.attachment_id)
        ),
        set: [used_confirmed_at: now, used_event_id: event_id, updated_at: now]
      )

    if count > 0, do: enqueue!(draft.tenant_id, draft.book_id)
  end

  def recalculate(tid, bid, after_id \\ nil) do
    Repo.transaction(fn ->
      Events.lock!("finance-setup:" <> bid)
      Events.lock!("enclosure-learning:" <> bid)

      if Repo.exists?(from t in Ep.Tenancy.Tenant, where: t.id == ^tid and t.status == "active") do
        query =
          from r in EnclosureLearningRecord,
            where: r.tenant_id == ^tid and r.book_id == ^bid and not is_nil(r.attachment_id),
            order_by: r.id,
            limit: 100

        query = if after_id, do: from(r in query, where: r.id > ^after_id), else: query
        records = Repo.all(query)

        if length(records) == 100 do
          Oban.insert!(
            Ep.Finance.EnclosureGuessWorker.new(%{
              tenant_id: tid,
              book_id: bid,
              after_id: List.last(records).id
            })
          )
        end

        Enum.each(records, fn record ->
          guess = EnclosureGuess.calculate(record)

          if guess != record.best_guess,
            do:
              Repo.update!(
                Ecto.Changeset.change(record,
                  best_guess: guess,
                  guess_version: record.guess_version + 1
                ),
                log: false
              )
        end)
      end

      :ok
    end)
  end

  def summaries(tid, bid, row_id) do
    Repo.all(
      from r in EnclosureLearningRecord,
        where:
          r.tenant_id == ^tid and r.book_id == ^bid and r.row_id == ^row_id and
            not is_nil(r.attachment_id),
        order_by: r.inserted_at
    )
    |> Enum.map(
      &Map.take(&1, [
        :id,
        :attachment_id,
        :best_guess,
        :initial_guess,
        :used_values,
        :guess_version
      ])
    )
  end

  def enqueue!(tid, bid),
    do: Oban.insert!(Ep.Finance.EnclosureGuessWorker.new(%{tenant_id: tid, book_id: bid}))

  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp valid_field?(field) when is_map(field) do
    Enum.sort(Map.keys(field)) == ~w(amount key label source value) && field["key"] in @keys &&
      is_boolean(field["amount"]) &&
      is_binary(field["label"]) && String.length(field["label"]) <= 80 &&
      is_binary(field["source"]) && String.length(field["source"]) <= 1000 &&
      if(field["amount"],
        do: is_integer(field["value"]) && abs(field["value"]) <= 9_000_000_000_000,
        else: is_binary(field["value"]) && String.length(field["value"]) <= 256
      )
  end

  defp valid_field?(_), do: false
end
