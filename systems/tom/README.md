# TOM — Tenant & Occasion Management

A separate Rails 8.1 / Ruby 3.4.4 application with Phlex and Tailwind CSS. TOM has no database, SQL client, Active Record, background worker or independent business-data store. Its backend calls EP over HTTP; browsers talk only to TOM.

## Start locally

Keep EP running at http://localhost:4000, then in another terminal:

```sh
cd systems/tom
bundle install
bin/dev
```

Open http://localhost:3000. `bin/dev` runs Puma and the Tailwind watcher without Foreman or Node. For a different EP origin, export `EP_BASE_URL=http://localhost:4000`; for a different TOM port export `PORT=3001`. `.env.example` is documentation, not automatically loaded.

Request a sign-in message in TOM. EP currently writes development messages to its private `systems/ep/tmp/magic_links/` directory. Paste the **single-use magic-link token**, not an existing Bearer session token, into TOM's sign-in form. TOM exchanges it with EP. Real email delivery and clickable magic-link callbacks remain future integration work.

Create a tenant, or open an existing tenant using its UUID. EP checks your current access on every tenant read. The tenant overview lists occasions and offers creation. Tenant listing, invitations, recruitment opening and delegation to other identities remain future work.

## Security and state

The EP Bearer token and its expiry are held in Rails' encrypted, authenticated, HttpOnly, SameSite=Lax session cookie. This cookie is browser-held encrypted state, not a server-side session database. Tokens never enter JavaScript, localStorage, URLs or rendered HTML. Production cookies require HTTPS. TOM checks expiry; EP remains responsible for current authorization and revocation. Protect `SECRET_KEY_BASE` and use the same secret across replicas.

Sign-out currently clears TOM's cookie; it does **not** revoke the EP session. A copied cookie remains usable until EP expiry/revocation. An EP revoke-session endpoint is required before production sign-out can promise server-side invalidation. No local token blacklist or identity database is introduced.

Forms use Rails CSRF protection; responses are `no-store`, credentials are filtered from Rails logs, and CSP disallows scripts and third-party resources. The fixed operator-configured EP origin prevents user-selected destinations; HTTPS is mandatory in production. The client has bounded timeouts and does not automatically retry requests. A session-held creation key survives uncertain outcomes for safe retries; EP owns authoritative deduplication. Local `/up` is TOM liveness, not EP readiness.

No cached tenant snapshot is served: pending projections can be refreshed, stopped projections fail closed, and foreign tenants remain unavailable. The last-opened tenant UUID is only a navigation hint in the encrypted session. Multiple tenants are supported through EP access checks, with no tenant scope inferred from client claims.

## Checks

```sh
PARALLEL_WORKERS=1 bin/rails test
bundle exec rubocop -a
bin/rails zeitwerk:check
bundle exec brakeman --no-pager
```

Tests stub EP HTTP, block external traffic, and need no PostgreSQL. See [architecture](docs/architecture.md), [roadmap](docs/roadmap.md) and [UI](docs/ui.md).

## Occasions

Apply EP's new migration, refresh your tenant overview and choose **Create occasion**. Enter a name, tenant-unique short name and expiry review date. TOM converts the end of that date in UTC to EP's timestamp. The checked “Assign me as occasion admin” option is explicit and may be cleared; it grants administration without participant membership. Recruitment remains closed.

The creation form and pending/ready detail screen use EP commands and materialized queries. The tenant overview lists projected occasions and can be refreshed. Duplicate short names and invalid fields retain form values; creation keys are tenant-bound and retained across uncertain responses. EP rechecks authority on the actual write even after a form was opened. Expiry review scheduling, retirement and recruitment opening are not implemented by this form.
