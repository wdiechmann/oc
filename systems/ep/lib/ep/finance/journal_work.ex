defmodule Ep.Finance.JournalWork do
  @moduledoc "Direct work-in-progress row edits; receipts and numbering commit with journal draft facts."
  import Ecto.Query
  alias Ep.{Events, Repo}
  alias Ep.Events.CommandReceipt

  alias Ep.Finance.{
    ChartImport,
    JournalAttachment,
    JournalDraft,
    JournalRow,
    JournalRows,
    Journals,
    Setup
  }

  def save(principal, tid, bid, mode, p, key, app \\ "internal")

  def save(principal, tid, bid, "post", p, key, app),
    do: Ep.Finance.JournalPosting.post(principal, tid, bid, p, key, app)

  def save(principal, tid, bid, mode, p, key, app) do
    scoped(principal, tid, bid, true, fn tid, bid ->
      unless mode in ~w(create row attachment details delete) && is_map(p) && is_binary(key) &&
               Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, key),
             do: Repo.rollback(:invalid_journal)

      type = "FinanceJournalWork:" <> mode
      Events.lock!("command:" <> principal.identity_id <> ":" <> type <> ":" <> key)
      fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({tid, bid, mode, p, app}))

      case Repo.get_by(CommandReceipt,
             identity_id: principal.identity_id,
             command_type: type,
             idempotency_key: key
           ) do
        %{fingerprint: ^fingerprint, result: result} ->
          Map.put(result, "replayed", true)

        nil ->
          {did, body} = build!(principal, tid, bid, mode, p, app)
          review = unwrap!(Journals.review(principal, tid, bid, body, app))
          inner_key = "work:" <> Base.encode16(:crypto.hash(:sha256, type <> key))

          result =
            unwrap!(
              Journals.accept(
                principal,
                tid,
                bid,
                Map.take(stringify(review), ~w(review_id digest expected_version)),
                inner_key,
                app
              )
            )

          result =
            if mode == "row" || (mode == "create" && p["initial_row"] == true) do
              id =
                get_in(p, ["row", "id"]) ||
                  Enum.at(
                    review.plan["data"]["rows"],
                    if(p["append_row"] == true, do: 1, else: 0)
                  )["id"]

              saved_row = Repo.get!(JournalRow, id)
              Map.merge(result, %{"row_id" => id, "posting_id" => saved_row.posting_id})
            else
              result
            end

          result =
            if p["append_row"] == true do
              next = hd(Repo.get!(JournalDraft, result["draft_id"]).data["rows"])

              Map.merge(result, %{
                "next_row_id" => next["id"],
                "next_posting_id" => next["posting_id"]
              })
            else
              result
            end

          if did && result["draft_id"] != did, do: Repo.rollback(:invalid_journal)

          Repo.insert!(%CommandReceipt{
            id: Ecto.UUID.generate(),
            identity_id: principal.identity_id,
            command_type: type,
            idempotency_key: key,
            fingerprint: fingerprint,
            result: result
          })

          result

        _ ->
          Repo.rollback(:idempotency_conflict)
      end
    end)
  end

  def lookup(principal, tid, bid, q) do
    query = q |> to_string() |> String.trim() |> String.slice(0, 120) |> String.downcase()

    with {:ok, data} <- Journals.get(principal, tid, bid) do
      if data.status != "ready",
        do: {:error, :view_pending},
        else:
          {:ok,
           %{
             source_version: data.contexts["setup_version"],
             results:
               data.accounts
               |> Enum.filter(fn a ->
                 a["active"] &&
                   (String.length(query) >= 2 || String.downcase(a["number"] || "") == query) &&
                   Enum.any?(
                     ~w(number name vat_code category vat_label category_label),
                     fn field ->
                       String.contains?(String.downcase(to_string(a[field] || "")), query)
                     end
                   )
               end)
               |> Enum.sort_by(
                 &{if(String.downcase(&1["number"] || "") == query, do: 0, else: 1), &1["number"]}
               )
               |> Enum.take(20)
           }}
    end
  end

  def attachments(principal, tid, bid, row_id) do
    scoped(principal, tid, bid, false, fn tid, bid ->
      row = row!(tid, bid, row_id)

      %{
        draft_id: row.draft_id,
        row_id: row.id,
        posting_id: row.posting_id,
        attachments: JournalRows.attachment_metadata(tid, bid, row.id)
      }
    end)
  end

  def stage(principal, tid, bid, row_id, p, app \\ "internal") do
    scoped(principal, tid, bid, true, fn tid, bid ->
      row = row!(tid, bid, row_id)

      unless is_map(p) && Enum.sort(Map.keys(p)) == ~w(content content_type filename) &&
               is_binary(p["content"]),
             do: Repo.rollback(:invalid_attachment)

      bytes =
        case Base.decode64(p["content"] || "") do
          {:ok, b} -> b
          _ -> Repo.rollback(:invalid_attachment)
        end

      valid =
        case p["content_type"] do
          "application/pdf" -> String.starts_with?(bytes, "%PDF-")
          "image/png" -> match?(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>, bytes)
          "image/jpeg" -> match?(<<255, 216, 255, _::binary>>, bytes)
          _ -> false
        end

      unless valid && byte_size(bytes) in 1..5_242_880 && is_binary(p["filename"]) &&
               String.length(p["filename"]) in 1..180 &&
               !Regex.match?(~r/[\p{Cc}\p{Cf}\/\\]/u, p["filename"]),
             do: Repo.rollback(:invalid_attachment)

      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      r =
        Repo.insert!(
          %ChartImport{
            tenant_id: tid,
            book_id: bid,
            identity_id: principal.identity_id,
            application_id: app,
            expires_at: expires,
            data: %{
              "purpose" => "journal_attachment",
              "row_id" => row.id,
              "filename" => p["filename"],
              "content_type" => p["content_type"],
              "content" => p["content"],
              "byte_size" => byte_size(bytes),
              "sha256" => Base.encode16(:crypto.hash(:sha256, bytes))
            }
          },
          log: false
        )

      Oban.insert!(
        Ep.Finance.ChartImportCleanupWorker.new(%{import_id: r.id, tenant_id: tid},
          scheduled_at: expires
        )
      )

      %{
        upload_id: r.id,
        row_id: row.id,
        filename: p["filename"],
        sha256: r.data["sha256"],
        byte_size: byte_size(bytes)
      }
    end)
  end

  def download(principal, tid, bid, id) do
    scoped(principal, tid, bid, false, fn tid, bid ->
      a =
        Repo.get_by(JournalAttachment, id: uuid!(id), tenant_id: tid, book_id: bid) ||
          Repo.rollback(:not_found)

      %{
        filename: a.filename,
        content_type: a.content_type,
        content: Base.encode64(a.bytes),
        sha256: a.sha256
      }
    end)
  end

  defp empty_row do
    %{
      "id" => nil,
      "reference" => "",
      "debit_account_id" => nil,
      "credit_account_id" => nil,
      "amount_minor" => 0,
      "amount_basis" => nil,
      "basis_override" => false,
      "credit_amount_minor" => nil,
      "void" => false
    }
  end

  defp build!(principal, tid, bid, mode, p, app) do
    allowed =
      case mode do
        "create" -> ~w(contexts data expected_version)
        "details" -> ~w(contexts data draft_id expected_draft_version expected_version)
        "delete" -> ~w(contexts draft_id expected_draft_version expected_version)
        "row" -> ~w(contexts draft_id expected_draft_version expected_version row)
        "attachment" -> ~w(contexts draft_id expected_draft_version expected_version upload_id)
      end

    checked =
      case mode do
        "create" -> Map.delete(p, "initial_row")
        "row" -> Map.delete(p, "append_row")
        _ -> p
      end

    unless Enum.sort(Map.keys(checked)) == allowed &&
             (mode != "create" || is_boolean(Map.get(p, "initial_row", false))) &&
             (mode != "row" || is_boolean(Map.get(p, "append_row", false))),
           do: Repo.rollback(:invalid_journal)

    if mode in ~w(create details) &&
         (!is_map(p["data"]) || Enum.sort(Map.keys(p["data"])) != ~w(name posting_date reference)),
       do: Repo.rollback(:invalid_journal)

    draft =
      if mode != "create",
        do:
          Repo.get_by(JournalDraft, tenant_id: tid, book_id: bid, id: uuid!(p["draft_id"])) ||
            Repo.rollback(:not_found)

    if draft && draft.data["deleted"], do: Repo.rollback(:not_found)
    if draft && draft.data["posted"], do: Repo.rollback(:journal_already_posted)

    data =
      if mode == "create",
        do:
          Map.put(
            p["data"],
            "rows",
            if(p["initial_row"] == true,
              do: [
                %{
                  "id" => nil,
                  "reference" => "",
                  "debit_account_id" => nil,
                  "credit_account_id" => nil,
                  "amount_minor" => 0,
                  "amount_basis" => nil,
                  "basis_override" => false,
                  "credit_amount_minor" => nil,
                  "void" => false
                }
              ],
              else: []
            )
          ),
        else:
          Map.take(draft.data, ~w(name posting_date reference))
          |> Map.put("rows", inputs(draft.data))

    data =
      case mode do
        "delete" ->
          rows =
            if is_list(draft.data["rows"]),
              do: Enum.map(data["rows"], &Map.put(&1, "void", true)),
              else: []

          data |> Map.put("rows", rows) |> Map.put("deleted", true)

        "details" ->
          Map.merge(data, Map.take(p["data"], ~w(name posting_date reference)))

        "row" ->
          row = p["row"]
          unless is_map(row), do: Repo.rollback(:invalid_journal)

          if row["id"] && !Enum.any?(data["rows"], &(&1["id"] == row["id"])),
            do: Repo.rollback(:invalid_journal)

          rows =
            if row["id"],
              do: Enum.map(data["rows"], fn r -> if r["id"] == row["id"], do: row, else: r end),
              else: [row | data["rows"]]

          rows =
            if p["append_row"] == true do
              if length(rows) >= 100, do: Repo.rollback(:journal_limit)
              [empty_row() | rows]
            else
              rows
            end

          Map.put(data, "rows", rows)

        "attachment" ->
          r =
            Repo.get_by(ChartImport,
              id: uuid!(p["upload_id"]),
              tenant_id: tid,
              book_id: bid,
              identity_id: principal.identity_id,
              application_id: app
            ) || Repo.rollback(:not_found)

          unless r.data["purpose"] == "journal_attachment" &&
                   DateTime.compare(r.expires_at, DateTime.utc_now()) == :gt &&
                   !r.accepted_command_id,
                 do: Repo.rollback(:review_expired)

          row = row!(tid, bid, r.data["row_id"])
          unless row.draft_id == draft.id, do: Repo.rollback(:not_found)

          if Repo.aggregate(from(a in JournalAttachment, where: a.row_id == ^row.id), :count) >=
               20,
             do: Repo.rollback(:invalid_attachment)

          Repo.insert!(
            %JournalAttachment{
              tenant_id: tid,
              book_id: bid,
              row_id: row.id,
              filename: r.data["filename"],
              content_type: r.data["content_type"],
              sha256: r.data["sha256"],
              byte_size: r.data["byte_size"],
              bytes: Base.decode64!(r.data["content"]),
              actor_identity_id: principal.identity_id
            },
            log: false
          )

          Repo.update!(Ecto.Changeset.change(r, accepted_command_id: Ecto.UUID.generate()))
          data

        _ ->
          data
      end

    {draft && draft.id,
     %{
       "draft_id" => draft && draft.id,
       "expected_draft_version" => p["expected_draft_version"],
       "expected_version" => p["expected_version"],
       "contexts" => p["contexts"],
       "data" => data
     }}
  end

  def inputs(%{"rows" => rows}), do: Enum.map(rows, &JournalRows.input/1)

  def inputs(data),
    do:
      Enum.map(data["lines"], fn l ->
        %{
          "id" => l["id"],
          "reference" => l["reference"],
          "debit_account_id" => if(l["debit_minor"] > 0, do: l["account_id"]),
          "credit_account_id" => if(l["credit_minor"] > 0, do: l["account_id"]),
          "amount_minor" => l["debit_minor"] + l["credit_minor"],
          "amount_basis" => "net",
          "void" => false
        }
      end)

  defp row!(tid, bid, id),
    do:
      Repo.get_by(JournalRow, id: uuid!(id), tenant_id: tid, book_id: bid) ||
        Repo.rollback(:not_found)

  defp scoped(principal, tid, bid, write, fun) do
    with {:ok, tid} <- Ecto.UUID.cast(tid), {:ok, bid} <- Ecto.UUID.cast(bid) do
      Repo.transaction(fn ->
        {_, _, steward} = Setup.authorize!(principal, tid, bid)
        if write && !steward, do: Repo.rollback(:not_found)
        fun.(tid, bid)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp uuid!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      _ -> Repo.rollback(:not_found)
    end
  end

  defp unwrap!({:ok, v}), do: v
  defp unwrap!({:error, r}), do: Repo.rollback(r)
  defp stringify(map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
end
