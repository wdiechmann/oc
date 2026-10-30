# VERA — Financial Control, Accounting and Settlement

VERA is a separate Rails client/backend for the finance domain in [system_2_plan.md](../../system_2_plan.md). It runs alongside TOM and talks to EP through HTTP APIs. It has no Active Record, local business database, Active Job, Action Cable, shared TOM sessions or direct PostgreSQL access.

## Run locally

Ruby 3.4.4 and Rails 8.1.4; all versions are pinned in Gemfile.lock. From this directory:

```sh
bin/setup --skip-server
bin/dev
```

Open **http://localhost:3001**. `bin/dev` runs Rails on loopback and Tailwind's watcher without Node/Foreman. `bin/rails server` also defaults to port 3001. `PORT` overrides the port and `EP_BASE_URL` overrides the fixed EP origin (default `http://localhost:4000`). `.env.example` documents configuration; Rails does not automatically load it.

`GET /up` checks VERA liveness. `GET /up/ep` performs a bounded readiness check against EP and returns 503 if unavailable, redirected or malformed. These endpoints do not imply that authentication or financial authority has been configured. The home page needs no EP connection.

## Sign in

Open **http://localhost:3001/session/new** and use the email of your existing identity managed through TOM. VERA requests a sign-in-only challenge from EP, delivers the VERA link, and stores its own encrypted-cookie session after explicit confirmation. It has no signup, invitation, recovery or identity-administration workflow. If the identity is unknown or throttled, the public response remains generic and no message is sent. A link opened by an email scanner does not redeem the challenge; the user must press Continue to VERA.

Development defaults to a private message file in **systems/vera/tmp/outbox**, not external email. Open its sign-in URL and confirm. SMTP delivery is configurable through the VERA-prefixed variables in .env.example. App URLs come from trusted configuration, not the incoming Host header. No bearer or magic-link secret is rendered into ordinary pages or event payloads.

After signing in, VERA asks EP for the user's currently authorized tenants/occasions. It does not create new permissions or treat tenant administration as financial posting authority. Tenant administrators can open their book registry as described below. The signed-out home page and liveness check still work without EP. Failures in submitted forms appear inline through Turbo with safe input preserved.

Sign out revokes this EP session and clears VERA's cookie; it does not sign the user out of TOM. If revocation cannot be confirmed, VERA still clears its browser session and explicitly reports the uncertainty; the EP session retains its normal expiry. These apps do not share cookie encryption keys or runtime secret files.

## EP backend credential and restart

`bin/setup` provisions a **separate** local `vera` backend credential through `bin/provision-ep-backend`. This explicit operator setup writes private ignored files at `systems/vera/config/ep_backend_token` and `systems/ep/config/backend_api_tokens.json`, retaining other registered entries and refusing mismatched VERA credentials. Each running application reads only its own file. No user identities, grants or tenants are created by provisioning.

After this feature's initial install, apply EP migrations and **restart both EP and VERA** to load their new schema/configuration, backend registration, dependencies and cookie configuration. The current development migration and credential have already been prepared in this workspace. Later setup runs retain the credential.

`VERA_EP_BACKEND_TOKEN` overrides VERA's local credential. In production provision that secret (or EP_BACKEND_TOKEN as a production-only fallback) independently, and register the matching `vera` entry in EP_BACKEND_TOKENS_JSON through the secret manager. The extra JSON file in EP is development-only; environment entries take precedence. Do not reuse TOM's credential or change its registration. Production also needs explicit HTTPS VERA_PUBLIC_BASE_URL/TOM_BASE_URL, SMTP credentials and the normal Rails deployment secrets.

EP owns accepted business records, current authority and query MVs. VERA uses only its API; no local database is introduced. Monetary finance commands, a general application-capability registry and VERA monitoring ingestion remain subsequent work.

## Tenant books

Sign in, then choose **Open books** on your tenant card. Create a draft book with a tenant-unique code, name, base currency, accounting-authority choice, timezone/year-start month and optional parent. Use the same form/model at every hierarchy level. Open its detail to rename or reparent it; EP protects current versions and rejects hierarchy cycles or foreign-tenant parents.

Apply EP migrations before using this slice (already applied to the local development database in this workspace). No new environment variables or application credentials are needed. Book metadata uses near-real-time query MVs; pending state and **Refresh books/book** distinguish acceptance from projection. A stopped MV is unavailable. A lost save response offers **Check completion**, which queries the original private command receipt without replaying the save.

The first-slice access policy is current tenant-admin authority for book **setup metadata** only. It grants no journal/posting/payment authority. Books stay Draft; no actual accounting period, CoA, opening balance, integration or consolidated total is created. Occasion-only admins do not gain tenant-wide setup access. Book-scoped configuration roles, occasion bindings and initial CoA editing are described below; periods and financial operations follow the plan. See the [EP book contract](../ep/docs/books-api.md).

## Roles, occasion bindings and accounts

From a book, choose **Roles and occasions**. A tenant administrator explicitly assigns a configuration steward for that book, including themselves when appropriate. Only assigned stewards can link occasions or edit the chart; roles do not inherit through the book tree and grant no journal/posting/payment authority. Stewards get a direct **Configure book** card on their VERA home page.

Link existing occasions there, then open the separate **Chart of accounts** line editor. Its columns are Type, Number, Name, VAT, Category, Position and Formula, with type-specific fields. Use list-focused Home/End/PgUp/PgDn/↑/↓, Enter to edit/save and Escape to cancel. will_paginate pages progressively append on scroll. Numbers keep leading zeroes and stay reserved after renumbering/deactivation/type changes. Formula text is validated and pinned to stable references; calculated ledger results follow later. Conflicts preserve the draft above the accepted row for explicit reapplication. Lost-response completion checks never repeat a mutation; an explicit retry after checking submits the unchanged original body/key. See the [finance setup contract](../ep/docs/finance-setup-api.md).

Apply the new EP migration (`mix ecto.migrate` in systems/ep; already applied in this local workspace) before using this slice. Restart EP/VERA when running without development code reloading. No credentials or financial grants are created by the migration, and existing tenant admins must explicitly assign their steward role. Batch reorder/rebalancing, configurable tax/category catalogues, reporting/formula results, import/export and monetary operations remain later work.

## Accounting periods

Open **Accounting periods** from the book, setup or chart. Create nonoverlapping inclusive date ranges as Draft, correct their dates before opening, then open/close them explicitly. Name/dates freeze on first opening. Reopening needs a recorded reason and a separate permission assigned to an existing book steward under Roles and occasions; tenant administration alone is insufficient. No reopening permission is assigned automatically.

EP protects current date/status/revisions and publishes the period/history query MV. Pending/stopped states, conflict drafts, private completion checks and exact-original retries follow the other financial setup workflows. The new local migration is already applied; other deployments must run `mix ecto.migrate`. See the [period contract](../ep/docs/periods-api.md). Period setup does not activate a book, post a journal, check balances or operate periods in an external ledger.

## Verification

```sh
bin/rails test
bundle exec rubocop --cache false
bin/rails zeitwerk:check
bundle exec brakeman --no-pager
```

Tests block real network connections and cover the landing page, database-free boot, dependency outage, malformed readiness responses, fixed-origin validation and redirect refusal. Tailwind is built as part of Rails tests. Browser verification uses Playwright.
