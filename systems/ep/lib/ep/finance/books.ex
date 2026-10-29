defmodule Ep.Finance.Books do
  @moduledoc "Tenant book-context setup. Current tenant administration authorizes metadata only, never posting or payment."
  import Ecto.Query
  alias Ep.{Repo, Events, Auth}
  alias Ep.Finance.{Book, BookView, BookWorker}
  alias Ep.Events.{CommandReceipt, Outbox}
  alias Ep.Projections.Control

  @create ~w(name code base_currency accounting_authority timezone fiscal_year_start_month parent_book_id)
  @fields [
    :tenant_id,
    :parent_book_id,
    :name,
    :code,
    :base_currency,
    :accounting_authority,
    :timezone,
    :fiscal_year_start_month,
    :status
  ]

  def create(principal, tid, params, key) do
    with {:ok, tid} <- uuid(tid), {:ok, attrs} <- validate(params), :ok <- valid_key(key) do
      Repo.transaction(fn ->
        authorize!(principal, tid)
        Events.lock!("finance-books:" <> tid)

        command!(principal, "FinanceBookCreate", key, {tid, attrs}, fn cid ->
          parent!(tid, attrs.parent_book_id, nil)

          if Repo.exists?(from b in Book, where: b.tenant_id == ^tid and b.code == ^attrs.code),
            do: Repo.rollback(:code_taken)

          control!(tid)
          book = Repo.insert!(struct!(Book, Map.put(attrs, :tenant_id, tid)))
          accept!(principal, book, cid, "BookCreated")
        end)
      end)
    end
  end

  def revise(principal, tid, id, params, key) do
    with {:ok, tid} <- uuid(tid),
         {:ok, id} <- uuid(id),
         :ok <- valid_key(key),
         true <-
           is_map(params) and
             Enum.all?(Map.keys(params), &(&1 in ~w(name parent_book_id expected_version))),
         version when is_integer(version) and version > 0 <- params["expected_version"],
         true <- Map.has_key?(params, "name") or Map.has_key?(params, "parent_book_id") do
      Repo.transaction(fn ->
        authorize!(principal, tid)
        Events.lock!("finance-books:" <> tid)

        command!(principal, "FinanceBookRevise", key, {tid, id, params}, fn cid ->
          book = Repo.get_by(Book, tenant_id: tid, id: id) || Repo.rollback(:not_found)
          unless book.version == version, do: Repo.rollback(:version_conflict)
          attrs = %{}

          attrs =
            if Map.has_key?(params, "name"),
              do: Map.put(attrs, :name, name!(params["name"])),
              else: attrs

          attrs =
            if Map.has_key?(params, "parent_book_id"),
              do: Map.put(attrs, :parent_book_id, optional_uuid!(params["parent_book_id"])),
              else: attrs

          parent!(tid, Map.get(attrs, :parent_book_id, book.parent_book_id), book.id)
          book = Repo.update!(Ecto.Changeset.change(book, attrs))
          accept!(principal, book, cid, "BookRevised")
        end)
      end)
    else
      _ -> {:error, :invalid_book}
    end
  end

  def list(principal, tid) do
    with {:ok, tid} <- uuid(tid) do
      Repo.transaction(fn ->
        tenant = authorize!(principal, tid)
        running!(tid)

        rows =
          Repo.all(
            from b in BookView,
              where: b.tenant_id == ^tid,
              order_by: [asc: fragment("?->>'code'", b.data)]
          )

        source = Enum.reduce(rows, 0, fn b, n -> max(n, b.source_version) end)
        latest = Repo.aggregate(from(b in Book, where: b.tenant_id == ^tid), :max, :version) || 0

        %{
          tenant_id: tid,
          tenant_name: tenant.name,
          status: if(source == latest, do: "ready", else: "pending"),
          source_version: source,
          latest_version: latest,
          books: Enum.map(rows, &present/1)
        }
      end)
    end
  end

  def get(principal, tid, id) do
    with {:ok, tid} <- uuid(tid), {:ok, id} <- uuid(id) do
      Repo.transaction(fn ->
        tenant = authorize!(principal, tid)
        running!(tid)
        current = Repo.get_by(Book, tenant_id: tid, id: id) || Repo.rollback(:not_found)
        row = Repo.get_by(BookView, tenant_id: tid, book_id: id)

        %{
          tenant_id: tid,
          book_id: id,
          tenant_name: tenant.name,
          status: if(row && row.source_version == current.version, do: "ready", else: "pending"),
          book: row && present(row),
          expected_version: current.version
        }
      end)
    end
  end

  def authorize!(principal, tid) do
    Auth.lock_principal!(principal)

    tenant =
      Repo.one(
        from t in Ep.Tenancy.Tenant,
          where: t.id == ^tid and t.status == "active",
          lock: "FOR SHARE"
      )

    access =
      Repo.one(
        from a in Ep.Tenancy.Access,
          where:
            a.tenant_id == ^tid and a.identity_id == ^principal.identity_id and
              a.status == "active" and a.role == "tenant_admin",
          lock: "FOR SHARE"
      )

    unless tenant && access, do: Repo.rollback(:not_found)
    tenant
  end

  def running!(tid) do
    control =
      Repo.one(
        from c in Control,
          where: c.tenant_id == ^tid and c.name == "finance_books",
          lock: "FOR SHARE"
      )

    if (control && control.state != "running") ||
         (is_nil(control) && Repo.exists?(from b in Book, where: b.tenant_id == ^tid)) do
      Repo.rollback(:view_stopped)
    end
  end

  defp control!(tid) do
    unless Repo.get_by(Control, tenant_id: tid, name: "finance_books"),
      do: Repo.insert!(%Control{tenant_id: tid, name: "finance_books"})
  end

  defp parent!(_, nil, _), do: :ok

  defp parent!(tid, id, self) do
    if id == self, do: Repo.rollback(:hierarchy_cycle)
    parent = Repo.get_by(Book, tenant_id: tid, id: id) || Repo.rollback(:invalid_parent)
    parent!(tid, parent.parent_book_id, self)
  end

  defp accept!(principal, book, cid, type) do
    snapshot =
      Map.take(book, @fields)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.put("book_id", book.id)

    [event] =
      Events.append!(
        %{
          scope: "tenant",
          scope_key: "tenant:" <> book.tenant_id,
          tenant_id: book.tenant_id,
          stream_type: "finance_books",
          stream_id: book.tenant_id,
          actor_identity_id: principal.identity_id,
          command_id: cid,
          correlation_id: cid
        },
        [{type, %{"book" => snapshot}}]
      )

    Repo.update!(Ecto.Changeset.change(book, version: event.stream_version))
    Repo.insert!(%Outbox{tenant_id: book.tenant_id, event_id: event.id})
    Oban.insert!(BookWorker.new(%{tenant_id: book.tenant_id}))

    %{
      "command_id" => cid,
      "book_id" => book.id,
      "tenant_id" => book.tenant_id,
      "event_ids" => [event.id],
      "stream_version" => event.stream_version
    }
  end

  defp command!(principal, type, key, attrs, fun) do
    Events.lock!("command:" <> principal.identity_id <> ":" <> type <> ":" <> key)
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(attrs))

    case Repo.get_by(CommandReceipt,
           identity_id: principal.identity_id,
           command_type: type,
           idempotency_key: key
         ) do
      nil ->
        cid = Ecto.UUID.generate()
        result = fun.(cid)

        Repo.insert!(%CommandReceipt{
          id: cid,
          identity_id: principal.identity_id,
          command_type: type,
          idempotency_key: key,
          fingerprint: digest,
          result: result
        })

        Map.put(result, "replayed", false)

      %{fingerprint: ^digest, result: result} ->
        Map.put(result, "replayed", true)

      _ ->
        Repo.rollback(:idempotency_conflict)
    end
  end

  defp validate(p) when is_map(p) do
    with true <- Enum.all?(Map.keys(p), &(&1 in @create)),
         name when is_binary(name) <- p["name"],
         true <- String.length(String.trim(name)) in 1..120,
         code when is_binary(code) <- p["code"],
         code = String.upcase(String.trim(code)),
         true <- Regex.match?(~r/^[A-Z0-9][A-Z0-9_-]{1,39}$/, code),
         true <- p["base_currency"] in ~w(DKK EUR SEK NOK GBP USD),
         true <- p["accounting_authority"] in ~w(ep external),
         true <- p["timezone"] in ["Europe/Copenhagen", "Etc/UTC"],
         month when is_integer(month) and month in 1..12 <- p["fiscal_year_start_month"],
         {:ok, parent} <- optional_uuid(p["parent_book_id"]) do
      {:ok,
       %{
         name: String.trim(name),
         code: code,
         base_currency: p["base_currency"],
         accounting_authority: p["accounting_authority"],
         timezone: p["timezone"],
         fiscal_year_start_month: month,
         parent_book_id: parent
       }}
    else
      _ -> {:error, :invalid_book}
    end
  end

  defp validate(_), do: {:error, :invalid_book}

  defp name!(name) when is_binary(name) do
    value = String.trim(name)
    if String.length(value) in 1..120, do: value, else: Repo.rollback(:invalid_book)
  end

  defp name!(_), do: Repo.rollback(:invalid_book)

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(v), do: uuid(v)

  defp optional_uuid!(v) do
    case optional_uuid(v) do
      {:ok, id} -> id
      _ -> Repo.rollback(:invalid_parent)
    end
  end

  defp valid_key(v) when is_binary(v),
    do: if(Regex.match?(~r/^[A-Za-z0-9._:-]{1,128}$/, v), do: :ok, else: {:error, :invalid_key})

  defp valid_key(_), do: {:error, :invalid_key}
  defp present(row), do: row.data |> Map.put("version", row.source_version)
end
