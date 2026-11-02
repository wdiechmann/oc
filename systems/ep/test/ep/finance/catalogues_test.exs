defmodule Ep.Finance.CataloguesTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers

  alias Ep.Finance.{
    Account,
    Books,
    CatalogueEntry,
    Catalogues,
    Setup,
    BookProjector,
    SetupProjector
  }

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Catalogues"}, "tenant")

    attrs = %{
      "name" => "Book",
      "code" => "BOOK",
      "base_currency" => "DKK",
      "accounting_authority" => "ep",
      "timezone" => "Europe/Copenhagen",
      "fiscal_year_start_month" => 1
    }

    {:ok, b} = Books.create(owner.principal, t["tenant_id"], attrs, "book")
    %{actor: owner.principal, tid: t["tenant_id"], bid: b["book_id"], book_attrs: attrs}
  end

  defp cmd(c, action, p, key \\ nil),
    do: Setup.command(c.actor, c.tid, c.bid, action, p, key || Ecto.UUID.generate())

  defp grant(c),
    do:
      cmd(c, "steward", %{
        "identity_id" => c.actor.identity_id,
        "active" => true,
        "expected_version" => 0
      })

  defp initialize(c, version),
    do: cmd(c, "catalogue_initialize", %{"expected_version" => version}, "initialize")

  defp entry(c, kind, code),
    do: Repo.get_by!(CatalogueEntry, book_id: c.bid, kind: kind, code: code)

  defp posting(version, number, pos),
    do: %{
      "name" => number,
      "kind" => "posting",
      "number" => number,
      "position" => pos,
      "expected_version" => version
    }

  defp revision(row, version, attrs),
    do:
      Map.merge(
        %{
          "entry_id" => row.id,
          "code" => row.code,
          "name" => row.name,
          "active" => row.active,
          "expected_version" => version,
          "expected_entry_version" => row.version
        },
        attrs
      )

  test "initialization explicitly adopts old selections with stable identities and preserves old accepted facts",
       c do
    assert {:error, :not_found} = initialize(c, 0)
    {:ok, _} = grant(c)

    {:ok, saved} =
      cmd(
        c,
        "account_create",
        Map.merge(posting(1, "0010", 100), %{"vat_code" => "input", "category" => "assets"})
      )

    id = hd(saved["event_ids"])
    old_payload = Repo.get!(Ep.Events.Details, id).payload

    assert {:ok, %{catalogues_initialized: false, catalogue_entries: []}} =
             Catalogues.get(c.actor, c.tid, c.bid)

    assert {:ok, _} = initialize(c, 2)
    assert {:ok, %{"replayed" => true}} = initialize(c, 2)

    assert {:error, :catalogues_initialized} =
             cmd(c, "catalogue_initialize", %{"expected_version" => 3})

    assert Repo.aggregate(CatalogueEntry, :count) == 8
    row = Repo.get!(Account, id)
    assert row.id == id && row.vat_code == "input" && row.category == "assets"
    assert row.vat_entry_id == entry(c, "vat", "input").id
    assert row.category_entry_id == entry(c, "category", "assets").id
    assert row.version == 3
    assert Repo.get!(Ep.Events.Details, id).payload == old_payload
    {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:ok, data} = Setup.accounts(c.actor, c.tid, c.bid)
    assert data.catalogues_initialized
    [account] = data.accounts
    assert account["vat_label"] == "Input VAT"
    assert Enum.map(data.options.vat_codes, & &1["code"]) == ["input", "none", "output"]
  end

  test "renames preserve references and reserve former codes; history and labels survive rebuild",
       c do
    {:ok, _} = grant(c)
    {:ok, _} = initialize(c, 1)
    vat = entry(c, "vat", "input")

    {:ok, saved} =
      cmd(c, "account_create", Map.put(posting(2, "0010", 100), "vat_entry_id", vat.id))

    id = hd(saved["event_ids"])
    before = Repo.get!(Account, id)

    assert {:ok, _} =
             cmd(
               c,
               "catalogue_revise",
               revision(vat, 3, %{"code" => "BUY", "name" => "Purchase classification"})
             )

    assert Repo.get!(Account, id).vat_entry_id == vat.id
    assert Repo.get!(Account, id).version == before.version
    assert Repo.get!(Account, id).vat_code == "input"

    assert {:error, :invalid_catalogue_reference} =
             cmd(c, "account_create", Map.put(posting(4, "0020", 200), "vat_code", "input"))

    assert {:error, :code_taken} =
             cmd(c, "catalogue_create", %{
               "kind" => "vat",
               "code" => "INPUT",
               "name" => "Duplicate",
               "expected_version" => 4
             })

    {:ok, _} = SetupProjector.deliver(c.tid)
    {:ok, chart} = Setup.accounts(c.actor, c.tid, c.bid)
    assert hd(chart.accounts)["vat_label"] == "Purchase classification"
    {:ok, data} = Catalogues.get(c.actor, c.tid, c.bid)
    projected = Enum.find(data.catalogue_entries, &(&1["id"] == vat.id))
    assert Enum.map(projected["history"], & &1["code"]) == ["input", "BUY"]
    event_count = Repo.aggregate(Ep.Events.Event, :count)
    jobs = Repo.aggregate(Oban.Job, :count)
    {:ok, :ok} = SetupProjector.rebuild(c.tid)
    assert Repo.aggregate(Ep.Events.Event, :count) == event_count
    assert Repo.aggregate(Oban.Job, :count) == jobs
    assert {:ok, %{catalogue_entries: entries}} = Catalogues.get(c.actor, c.tid, c.bid)
    assert Enum.find(entries, &(&1["id"] == vat.id)) == projected

    retain =
      Map.merge(posting(4, "0010", 100), %{
        "account_id" => id,
        "active" => true,
        "expected_account_version" => 3,
        "vat_code" => "input"
      })

    assert {:ok, _} = cmd(c, "account_revise", retain)
    assert Repo.get!(Account, id).vat_code == "BUY"
    assert Repo.get!(Account, id).vat_entry_version == 4

    assert {:ok, _} =
             cmd(c, "account_revise", %{
               retain
               | "expected_version" => 5,
                 "expected_account_version" => 5
             })

    assert Repo.get!(Account, id).vat_entry_id == vat.id
  end

  test "deactivation permits retained associations but rejects new assignments and stale saves",
       c do
    {:ok, _} = grant(c)
    {:ok, _} = initialize(c, 1)
    vat = entry(c, "vat", "input")

    {:ok, saved} =
      cmd(c, "account_create", Map.put(posting(2, "0010", 100), "vat_entry_id", vat.id))

    id = hd(saved["event_ids"])
    assert {:ok, _} = cmd(c, "catalogue_revise", revision(vat, 3, %{"active" => false}))

    assert {:error, :version_conflict} =
             cmd(c, "account_create", Map.put(posting(3, "0020", 200), "vat_entry_id", vat.id))

    assert {:error, :inactive_catalogue_entry} =
             cmd(c, "account_create", Map.put(posting(4, "0020", 200), "vat_entry_id", vat.id))

    retain =
      Map.merge(posting(4, "0010", 100), %{
        "account_id" => id,
        "active" => true,
        "expected_account_version" => 3,
        "vat_entry_id" => vat.id
      })

    assert {:ok, _} = cmd(c, "account_revise", retain)
    assert Repo.get!(Account, id).vat_entry_id == vat.id

    assert {:ok, _} =
             cmd(c, "account_revise", %{
               retain
               | "expected_version" => 5,
                 "expected_account_version" => 5,
                 "vat_entry_id" => nil
             })

    assert Repo.get!(Account, id).vat_entry_id == nil
    deactivated = Repo.get!(CatalogueEntry, vat.id)
    assert {:ok, _} = cmd(c, "catalogue_revise", revision(deactivated, 6, %{"active" => true}))

    assert {:ok, _} =
             cmd(c, "account_create", Map.put(posting(7, "0020", 200), "vat_entry_id", vat.id))
  end

  test "scope/kind, current authority and initialized state govern every command and replay", c do
    {:ok, _} = grant(c)

    assert {:error, :catalogue_not_initialized} =
             cmd(c, "catalogue_create", %{
               "kind" => "vat",
               "code" => "NEW",
               "name" => "New",
               "expected_version" => 1
             })

    assert {:error, :catalogue_not_initialized} =
             cmd(c, "account_create", Map.put(posting(1, "0010", 100), "vat_entry_id", nil))

    {:ok, _} = initialize(c, 1)
    category = entry(c, "category", "assets")

    assert {:error, :invalid_catalogue_reference} =
             cmd(
               c,
               "account_create",
               Map.put(posting(2, "0010", 100), "vat_entry_id", category.id)
             )

    {:ok, other} = Books.create(c.actor, c.tid, %{c.book_attrs | "code" => "OTHER"}, "other")

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        other["book_id"],
        "steward",
        %{"identity_id" => c.actor.identity_id, "active" => true, "expected_version" => 0},
        "other-role"
      )

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        other["book_id"],
        "catalogue_initialize",
        %{"expected_version" => 1},
        "other-init"
      )

    foreign = Repo.get_by!(CatalogueEntry, book_id: other["book_id"], kind: "vat", code: "input")

    assert {:error, :invalid_catalogue_reference} =
             cmd(
               c,
               "account_create",
               Map.put(posting(2, "0010", 100), "vat_entry_id", foreign.id)
             )

    assert {:error, :not_found} = cmd(c, "catalogue_revise", revision(foreign, 2, %{}))

    {:ok, _} =
      cmd(c, "steward", %{
        "identity_id" => c.actor.identity_id,
        "active" => false,
        "expected_version" => 2
      })

    assert {:error, :not_found} = initialize(c, 1)
    assert {:error, :not_found} = Catalogues.get(sign_in().principal, c.tid, c.bid)
  end

  test "entry validation and stopped views reject partial or stale catalogue success", c do
    {:ok, _} = grant(c)
    {:ok, _} = initialize(c, 1)

    for changed <- [
          %{"kind" => "tax_rate"},
          %{"code" => "bad code"},
          %{"name" => "  "},
          %{"rate" => 25}
        ] do
      assert {:error, :invalid_catalogue} =
               cmd(
                 c,
                 "catalogue_create",
                 Map.merge(
                   %{"kind" => "vat", "code" => "NEW", "name" => "New", "expected_version" => 2},
                   changed
                 )
               )
    end

    assert {:ok, _} =
             cmd(
               c,
               "catalogue_create",
               %{
                 "kind" => "category",
                 "code" => "NEW",
                 "name" => "New category",
                 "expected_version" => 2
               },
               "create-entry"
             )

    assert {:error, :idempotency_conflict} =
             cmd(
               c,
               "catalogue_create",
               %{
                 "kind" => "category",
                 "code" => "NEW2",
                 "name" => "New category",
                 "expected_version" => 2
               },
               "create-entry"
             )

    assert Repo.aggregate(CatalogueEntry, :count) == 9

    Repo.update_all(
      from(x in Ep.Projections.Control,
        where: x.tenant_id == ^c.tid and x.name == "finance_setup"
      ),
      set: [state: "stopped"]
    )

    assert {:error, :view_stopped} = Catalogues.get(c.actor, c.tid, c.bid)
    assert {:error, :view_stopped} = SetupProjector.deliver(c.tid)
    assert {:ok, _} = BookProjector.deliver(c.tid)
  end
end
