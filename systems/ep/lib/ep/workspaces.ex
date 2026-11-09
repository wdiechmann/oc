defmodule Ep.Workspaces do
  @moduledoc "Current authorized navigation from scoped projections, never from session-side role claims."
  import Ecto.Query
  alias Ep.{Auth, Repo}

  def list(principal) do
    Repo.transaction(fn ->
      i = Auth.lock_principal!(principal)

      tenants =
        Repo.all(
          from(a in Ep.Tenancy.Access,
            join: t in Ep.Tenancy.Tenant,
            on: t.id == a.tenant_id,
            join: d in Ep.Projections.TenantDirectory,
            on: d.tenant_id == t.id,
            join: c in Ep.Projections.Control,
            on: c.tenant_id == t.id and c.name == "tenant_directory",
            where:
              a.identity_id == ^i.id and a.status == "active" and a.role == "tenant_admin" and
                t.status == "active" and c.state == "running",
            order_by: [d.name, d.tenant_id],
            select: %{tenant_id: t.id, name: d.name, role: a.role}
          )
        )

      occasions =
        Repo.all(
          from(a in Ep.Occasions.Admin,
            join: o in Ep.Occasions.Occasion,
            on: o.id == a.occasion_id and o.tenant_id == a.tenant_id,
            join: t in Ep.Tenancy.Tenant,
            on: t.id == o.tenant_id,
            join: d in Ep.Occasions.Directory,
            on: d.tenant_id == o.tenant_id and d.occasion_id == o.id,
            join: c in Ep.Projections.Control,
            on: c.tenant_id == t.id and c.name == "occasion_directory",
            where:
              a.identity_id == ^i.id and a.status == "active" and o.status in ["draft", "active"] and
                t.status == "active" and c.state == "running",
            order_by: [d.name, o.id],
            select: %{
              tenant_id: t.id,
              occasion_id: o.id,
              name: d.name,
              tenant_name: t.name,
              role: "occasion_admin"
            }
          )
        )

      finance_books =
        Repo.all(
          from s in Ep.Finance.Steward,
            join: t in Ep.Tenancy.Tenant,
            on: t.id == s.tenant_id,
            join: v in Ep.Finance.BookView,
            on: v.tenant_id == s.tenant_id and v.book_id == s.book_id,
            join: c in Ep.Projections.Control,
            on: c.tenant_id == s.tenant_id and c.name == "finance_books",
            join: f in Ep.Projections.Control,
            on: f.tenant_id == s.tenant_id and f.name == "finance_setup",
            where:
              s.identity_id == ^i.id and s.active and t.status == "active" and
                c.state == "running" and f.state == "running",
            order_by: s.book_id,
            select: %{
              tenant_id: s.tenant_id,
              book_id: s.book_id,
              name: fragment("?->>'name'", v.data),
              tenant_name: t.name,
              role: "finance_configuration_steward"
            }
        )

      tenant_ids = Enum.map(tenants, & &1.tenant_id)
      book_ids = Enum.map(finance_books, & &1.book_id)

      linked =
        Repo.all(
          from b in Ep.Finance.Binding,
            join: o in Ep.Occasions.Occasion,
            on: o.id == b.occasion_id and o.tenant_id == b.tenant_id,
            join: d in Ep.Occasions.Directory,
            on: d.occasion_id == o.id and d.tenant_id == b.tenant_id,
            join: t in Ep.Tenancy.Tenant,
            on: t.id == b.tenant_id,
            join: v in Ep.Finance.BookView,
            on: v.book_id == b.book_id and v.tenant_id == b.tenant_id,
            join: bc in Ep.Projections.Control,
            on: bc.tenant_id == b.tenant_id and bc.name == "finance_books",
            join: sc in Ep.Projections.Control,
            on: sc.tenant_id == b.tenant_id and sc.name == "finance_setup",
            join: oc in Ep.Projections.Control,
            on: oc.tenant_id == b.tenant_id and oc.name == "occasion_directory",
            where:
              (b.tenant_id in ^tenant_ids or b.book_id in ^book_ids) and t.status == "active" and
                o.status in ["draft", "active"] and bc.state == "running" and
                sc.state == "running" and oc.state == "running",
            select: %{
              tenant_id: b.tenant_id,
              occasion_id: o.id,
              name: d.name,
              tenant_name: t.name,
              book_id: b.book_id,
              book_name: fragment("?->>'name'", v.data)
            }
        )

      by_occasion = Map.new(linked, &{&1.occasion_id, &1})

      occasions =
        Enum.map(occasions, fn occasion ->
          Map.merge(
            occasion,
            Map.take(by_occasion[occasion.occasion_id] || %{}, [:book_id, :book_name])
          )
        end)

      known = MapSet.new(occasions, & &1.occasion_id)

      occasions =
        (occasions ++
           Enum.map(
             Enum.reject(linked, &MapSet.member?(known, &1.occasion_id)),
             &Map.put(&1, :role, "linked_occasion")
           ))
        |> Enum.sort_by(&{&1.name, &1.occasion_id})

      %{tenants: tenants, occasions: occasions, finance_books: finance_books}
    end)
  end
end
