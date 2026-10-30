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

      %{tenants: tenants, occasions: occasions, finance_books: finance_books}
    end)
  end
end
