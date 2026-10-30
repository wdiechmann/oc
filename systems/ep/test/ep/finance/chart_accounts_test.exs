defmodule Ep.Finance.ChartAccountsTest do
  use Ep.DataCase, async: true
  import Ep.Support.AuthHelpers
  alias Ep.Finance.{Account, Books, Setup, SetupProjector}

  setup do
    owner = sign_in()

    {:ok, %{result: t}} =
      Ep.Tenancy.create_tenant(owner.principal, %{"name" => "Chart"}, "tenant")

    tid = t["tenant_id"]

    {:ok, b} =
      Books.create(
        owner.principal,
        tid,
        %{
          "code" => "CHART",
          "name" => "Chart",
          "base_currency" => "DKK",
          "accounting_authority" => "ep",
          "timezone" => "Europe/Copenhagen",
          "fiscal_year_start_month" => 1
        },
        "book"
      )

    bid = b["book_id"]

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

    %{actor: owner.principal, tid: tid, bid: bid}
  end

  defp command(c, action, attrs),
    do: Setup.command(c.actor, c.tid, c.bid, action, attrs, Ecto.UUID.generate())

  defp posting(version, number, position),
    do: %{
      "kind" => "posting",
      "number" => number,
      "name" => "Account " <> number,
      "vat_code" => "input",
      "category" => "assets",
      "position" => position,
      "expected_version" => version
    }

  test "row types clear irrelevant fields and accept only governed dropdown values and positions",
       c do
    assert {:ok, header} =
             command(c, "account_create", %{
               "kind" => "header",
               "name" => "Assets",
               "position" => 100,
               "number" => "ignored",
               "vat_code" => "ignored",
               "formula" => "ignored",
               "expected_version" => 1
             })

    row = Repo.get!(Account, hd(header["event_ids"]))
    assert row.number == nil && row.vat_code == nil && row.category == nil && row.formula == nil
    assert row.position == 100
    assert {:ok, _} = command(c, "account_create", posting(2, "0010", 200))
    assert {:error, :position_taken} = command(c, "account_create", posting(3, "0020", 200))

    for attrs <- [
          Map.put(posting(3, "0020", 300), "vat_code", "unknown"),
          Map.put(posting(3, "0020", 300), "category", "unknown"),
          Map.put(posting(3, "0020", 300), "position", nil)
        ] do
      assert {:error, :invalid_setup} = command(c, "account_create", attrs)
    end

    {:ok, _} = SetupProjector.deliver(c.tid)

    assert {:ok,
            %{
              accounts: [
                %{"kind" => "header", "number" => nil},
                %{"number" => "0010", "vat_code" => "input", "category" => "assets"}
              ]
            }} = Setup.accounts(c.actor, c.tid, c.bid)
  end

  test "formulas pin stable references, reject foreign/missing/header/cyclic references and never execute text",
       c do
    {:ok, p} = command(c, "account_create", posting(1, "0010", 100))
    pid = hd(p["event_ids"])

    calc = %{
      "kind" => "calculation",
      "name" => "Total",
      "position" => 200,
      "formula" => "[0010] * (1 + 0.25)",
      "expected_version" => 2
    }

    assert {:ok, r} = command(c, "account_create", calc)
    cid = hd(r["event_ids"])
    assert Repo.get!(Account, cid).formula_refs == %{"0010" => pid}

    assert {:ok, _} =
             command(
               c,
               "account_revise",
               Map.merge(posting(3, "0020", 100), %{
                 "account_id" => pid,
                 "active" => true,
                 "expected_account_version" => 2
               })
             )

    assert {:ok, _} =
             command(
               c,
               "account_revise",
               Map.merge(calc, %{
                 "account_id" => cid,
                 "active" => true,
                 "expected_version" => 4,
                 "expected_account_version" => 3
               })
             )

    assert Repo.get!(Account, cid).formula_refs == %{"0010" => pid}

    assert {:ok, r2} =
             command(c, "account_create", %{
               calc
               | "position" => 300,
                 "formula" => "[@#{cid}] + 10",
                 "expected_version" => 5
             })

    c2id = hd(r2["event_ids"])

    assert {:error, :invalid_formula} =
             command(
               c,
               "account_revise",
               Map.merge(calc, %{
                 "account_id" => cid,
                 "active" => true,
                 "formula" => "[@#{c2id}]",
                 "expected_version" => 6,
                 "expected_account_version" => 5
               })
             )

    assert {:error, :invalid_formula} =
             command(c, "account_revise", %{
               "account_id" => pid,
               "kind" => "header",
               "name" => "No longer a posting account",
               "position" => 100,
               "active" => true,
               "expected_version" => 6,
               "expected_account_version" => 4
             })

    for formula <- [
          "[9999]",
          "[@#{Ecto.UUID.generate()}]",
          "System.cmd(\"touch\", [])",
          "[0020] +",
          ""
        ] do
      assert {:error, :invalid_formula} =
               command(c, "account_create", %{
                 calc
                 | "position" => 400,
                   "formula" => formula,
                   "expected_version" => 6
               })
    end

    {:ok, _} = SetupProjector.deliver(c.tid)
    assert {:ok, :ok} = SetupProjector.rebuild(c.tid)
    {:ok, data} = Setup.accounts(c.actor, c.tid, c.bid)
    assert Enum.find(data.accounts, &(&1["id"] == cid))["formula_refs"] == %{"0010" => pid}
  end

  test "pagination follows canonical position and fences appended pages to one ready projection",
       c do
    for {position, version} <- [{300, 1}, {100, 2}, {200, 3}] do
      {:ok, _} =
        command(c, "account_create", posting(version, Integer.to_string(position), position))
    end

    {:ok, _} = SetupProjector.deliver(c.tid)

    assert {:ok,
            %{
              accounts: [%{"position" => 100}, %{"position" => 200}],
              pagination: %{page: 1, total_entries: 3, total_pages: 2},
              source_version: 4
            }} = Setup.accounts(c.actor, c.tid, c.bid, %{"page" => "1", "per_page" => "2"})

    assert {:ok, %{accounts: [%{"position" => 300}]}} =
             Setup.accounts(c.actor, c.tid, c.bid, %{
               "page" => "2",
               "per_page" => "2",
               "source_version" => "4"
             })

    {:ok, _} = command(c, "account_create", posting(4, "400", 400))

    assert {:error, :chart_changed} =
             Setup.accounts(c.actor, c.tid, c.bid, %{"page" => "2", "source_version" => "4"})

    {:ok, _} = SetupProjector.deliver(c.tid)

    assert {:error, :chart_changed} =
             Setup.accounts(c.actor, c.tid, c.bid, %{"page" => "2", "source_version" => "4"})

    assert {:ok, %{pagination: %{total_entries: 1}, accounts: [%{"number" => "400"}]}} =
             Setup.accounts(c.actor, c.tid, c.bid, %{"q" => "400"})

    for params <- [%{"page" => "0"}, %{"page" => %{}}, %{"per_page" => "101"}, %{"q" => []}] do
      assert {:error, :invalid_setup} = Setup.accounts(c.actor, c.tid, c.bid, params)
    end
  end
end
