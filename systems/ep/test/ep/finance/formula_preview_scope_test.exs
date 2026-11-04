defmodule Ep.Finance.FormulaPreviewScopeTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Account, Books, ChartImports, FormulaPreview, Setup, SetupProjector}

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Ordering"}, "tenant")

    tid = t["tenant_id"]

    {:ok, book} =
      Books.create(
        owner.principal,
        tid,
        %{
          "name" => "Order",
          "code" => "ORDER",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = book["book_id"]

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "steward",
        %{
          "identity_id" => owner.principal.identity_id,
          "active" => true,
          "expected_version" => 0
        },
        "grant"
      )

    {:ok, _} =
      Setup.command(
        owner.principal,
        tid,
        bid,
        "catalogue_initialize",
        %{"expected_version" => 1},
        "initialize"
      )

    {:ok, _} = SetupProjector.deliver(tid)

    {:ok, upload} =
      ChartImports.upload(owner.principal, tid, bid, %{
        "headers" => ~w(type number name position formula),
        "records" => [
          ["posting", "0010", "Bank", "10", ""],
          ["header", "", "Header", "20", ""],
          ["calculation", "", "Total", "30", "[0010] * 2"]
        ]
      })

    {:ok, preview} =
      ChartImports.preview(owner.principal, tid, bid, upload.import_id, %{
        "mapping" => upload.mapping
      })

    {:ok, _} =
      ChartImports.accept(
        owner.principal,
        tid,
        bid,
        upload.import_id,
        %{"digest" => preview.digest, "expected_version" => preview.expected_version},
        "seed"
      )

    {:ok, _} = SetupProjector.deliver(tid)
    %{actor: owner.principal, token: owner.token, tid: tid, bid: bid, csv_review: preview}
  end

  test "read-only scoped preview fences revisions, validates balances and writes no facts", c do
    {:ok, data} = FormulaPreview.get(c.actor, c.tid, c.bid)
    [posting] = Enum.filter(data.rows, &(&1["kind"] == "posting"))
    params = %{"expected_version" => data.source_version, "balances" => %{posting["id"] => 25}}
    before_events = Repo.aggregate(Ep.Events.Event, :count)
    {:ok, preview} = FormulaPreview.preview(c.actor, c.tid, c.bid, params)
    assert hd(preview.results).amount_minor == 50
    assert Repo.aggregate(Ep.Events.Event, :count) == before_events

    assert {:error, :version_conflict} =
             FormulaPreview.preview(c.actor, c.tid, c.bid, %{params | "expected_version" => 0})

    assert {:error, :invalid_preview} =
             FormulaPreview.preview(c.actor, c.tid, c.bid, %{
               params
               | "expected_version" => data.source_version / 1
             })

    for value <- [1.5, "25", nil, 9_000_000_000_001] do
      assert {:error, :invalid_balances} =
               FormulaPreview.preview(c.actor, c.tid, c.bid, %{
                 params
                 | "balances" => %{posting["id"] => value}
               })
    end

    assert {:error, :invalid_balances} =
             FormulaPreview.preview(c.actor, c.tid, c.bid, %{
               params
               | "balances" => %{Ecto.UUID.generate() => 1}
             })

    assert {:error, :not_found} = FormulaPreview.get(sign_in().principal, c.tid, c.bid)
    assert {:error, :not_found} = FormulaPreview.get(c.actor, Ecto.UUID.generate(), c.bid)

    {:ok, _} =
      Setup.command(
        c.actor,
        c.tid,
        c.bid,
        "steward",
        %{
          "identity_id" => c.actor.identity_id,
          "active" => false,
          "expected_version" => data.source_version
        },
        "revoke"
      )

    # The tenant administrator still has read authority, but the view must first catch up.
    assert {:error, :view_pending} = FormulaPreview.preview(c.actor, c.tid, c.bid, params)
    {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:ok, _} = FormulaPreview.get(c.actor, c.tid, c.bid)
    assert Repo.get!(Account, posting["id"]).number == "0010"
  end
end
