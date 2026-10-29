defmodule Ep.Finance.BooksTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Books, BookProjector, Book}

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Books"}, "tenant")

    %{owner: owner, tid: t["tenant_id"]}
  end

  def attrs(code, parent \\ nil),
    do: %{
      "code" => code,
      "name" => code,
      "base_currency" => "DKK",
      "accounting_authority" => "ep",
      "timezone" => "Europe/Copenhagen",
      "fiscal_year_start_month" => 1,
      "parent_book_id" => parent
    }

  test "accepted book setup is idempotent and the ordinary read waits for its MV", c do
    assert {:ok, r} = Books.create(c.owner.principal, c.tid, attrs("SL2030"), "create")
    assert r["book_id"]

    assert {:ok, %{"replayed" => true}} =
             Books.create(c.owner.principal, c.tid, attrs("SL2030"), "create")

    assert {:error, :idempotency_conflict} =
             Books.create(c.owner.principal, c.tid, attrs("OTHER"), "create")

    assert Repo.aggregate(Book, :count) == 1
    assert {:ok, %{status: "pending", books: []}} = Books.list(c.owner.principal, c.tid)
    assert {:ok, 1} = BookProjector.deliver(c.tid)
    assert {:ok, 0} = BookProjector.deliver(c.tid)

    assert {:ok, %{status: "ready", book: %{"code" => "SL2030"}}} =
             Books.get(c.owner.principal, c.tid, r["book_id"])

    assert {:error, :code_taken} =
             Books.create(c.owner.principal, c.tid, attrs("sl2030"), "another")
  end

  test "hierarchy is tenant-local and cycle-safe; stale edits cannot overwrite a book", c do
    {:ok, a} = Books.create(c.owner.principal, c.tid, attrs("GROUP"), "a")
    {:ok, b} = Books.create(c.owner.principal, c.tid, attrs("CHILD", a["book_id"]), "b")

    assert {:error, :hierarchy_cycle} =
             Books.revise(
               c.owner.principal,
               c.tid,
               a["book_id"],
               %{"expected_version" => a["stream_version"], "parent_book_id" => b["book_id"]},
               "cycle"
             )

    assert {:ok, r} =
             Books.revise(
               c.owner.principal,
               c.tid,
               b["book_id"],
               %{"expected_version" => b["stream_version"], "name" => "Updated"},
               "rename"
             )

    assert {:ok, %{"replayed" => true}} =
             Books.revise(
               c.owner.principal,
               c.tid,
               b["book_id"],
               %{"expected_version" => b["stream_version"], "name" => "Updated"},
               "rename"
             )

    assert {:error, :version_conflict} =
             Books.revise(
               c.owner.principal,
               c.tid,
               b["book_id"],
               %{"expected_version" => b["stream_version"], "name" => "Stale"},
               "stale"
             )

    assert Repo.get!(Book, b["book_id"]).version == r["stream_version"]
    stranger = sign_in()
    assert {:error, :not_found} = Books.list(stranger.principal, c.tid)

    {:ok, %{result: other}} =
      Ep.Tenancy.create_tenant(stranger.principal, %{"name" => "Other"}, "other")

    {:ok, foreign} =
      Books.create(stranger.principal, other["tenant_id"], attrs("FOREIGN"), "foreign")

    assert {:error, :invalid_parent} =
             Books.create(
               c.owner.principal,
               c.tid,
               attrs("BAD", foreign["book_id"]),
               "foreign-parent"
             )

    assert {:error, :not_found} = Books.get(c.owner.principal, other["tenant_id"], a["book_id"])
  end

  test "revocation and stopped query controls are checked at use time", c do
    {:ok, r} = Books.create(c.owner.principal, c.tid, attrs("BOOK"), "book")
    {:ok, _} = BookProjector.deliver(c.tid)

    control_query =
      from x in Ep.Projections.Control, where: x.tenant_id == ^c.tid and x.name == "finance_books"

    Repo.update_all(control_query, set: [state: "stopped"])

    assert {:error, :view_stopped} = Books.list(c.owner.principal, c.tid)
    assert {:error, :view_stopped} = BookProjector.deliver(c.tid)

    Repo.update_all(from(x in Ep.Tenancy.Access, where: x.tenant_id == ^c.tid),
      set: [status: "revoked"]
    )

    assert {:error, :not_found} = Books.create(c.owner.principal, c.tid, attrs("BOOK"), "book")
    assert {:error, :not_found} = Books.get(c.owner.principal, c.tid, r["book_id"])
  end

  test "recovery includes book publication and metadata rebuild creates no new facts or jobs",
       c do
    {:ok, _} = Books.create(c.owner.principal, c.tid, attrs("REPLAY"), "replay")
    assert {:ok, _} = Ep.Outbox.requeue_pending()
    assert Repo.exists?(from j in Oban.Job, where: j.worker == "Ep.Finance.BookWorker")
    {:ok, _} = BookProjector.deliver(c.tid)
    before_events = Repo.aggregate(Ep.Events.Event, :count)
    before_jobs = Repo.aggregate(Oban.Job, :count)
    assert {:ok, :ok} = BookProjector.rebuild(c.tid)
    assert Repo.aggregate(Ep.Events.Event, :count) == before_events
    assert Repo.aggregate(Oban.Job, :count) == before_jobs

    assert {:ok, %{status: "ready", books: [%{"code" => "REPLAY"}]}} =
             Books.list(c.owner.principal, c.tid)
  end
end
