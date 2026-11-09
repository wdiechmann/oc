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

Development defaults to a private message file in **systems/vera/tmp/outbox**, not external email. The flash notice shows a clickable development sign-in URL; open it and confirm. SMTP delivery is configurable through the VERA-prefixed variables in .env.example. App URLs come from trusted configuration, not the incoming Host header. Bearer credentials never appear in pages; production pages and event payloads omit magic-link secrets. The development flash is the explicit exception for local sign-in.

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

Apply the new EP migration (`mix ecto.migrate` in systems/ep; already applied in this local workspace) before using this slice. Restart EP/VERA when running without development code reloading. No credentials or financial grants are created by the migration, and existing tenant admins must explicitly assign their steward role. Batch reorder/rebalancing, effective tax/rate/rule configuration, reporting/formula results, import/export and monetary operations remain later work.

## VAT and category catalogues

Open **VAT and categories** from a book, setup or chart. A book steward must press **Initialize catalogues** once: this adopts the former choices and binds existing account selections to stable IDs in one accepted batch. The chart is readonly until adoption is projected, preserving legacy selections. The local schema migration is applied, but no user book is initialized automatically.

Create entries, rename code/name and deactivate/reactivate them. Existing associations survive changes, inactive entries remain on their own accounts, and new assignments require current active entries from the correct book/catalogue. Former codes stay reserved. Catalogue history, conflict drafts, pending/stopped views and receipt recovery use the existing setup pipeline. See [catalogues-api.md](../ep/docs/catalogues-api.md). These VAT entries are classification labels; tax rates/calculation/posting rules remain later work.

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

## Portable document scanning and production image

Enclosure review automatically scans visible PDF, PNG and JPEG previews for suggested supplier, invoice number/date, due date, CVR/VAT number, currency, net amount, VAT and total. Text PDFs use Poppler; scanned PDFs/images use Tesseract. Suggestions include their source lines; competing values remain candidates. On Attach enclosure they can seed a financially empty draft row for review; they never replace existing row values, change VAT rules or grant posting authority. All processing runs locally on the VERA server: no external OCR/AI service receives documents.

The production Dockerfile uses Linux Ruby 3.4.4, installs `poppler-utils`, `tesseract-ocr`, `tesseract-ocr-dan` and `tesseract-ocr-eng`, precompiles assets and runs as a nonroot user. Gemfile.lock includes Linux amd64/arm64 platforms as well as local macOS. From this directory:

```sh
docker build -t vera .
docker run --rm --env-file /secure/vera-production.env -p 127.0.0.1:3001:3001 vera
```

Provision the normal Rails secret, VERA/EP backend credential, trusted public URLs and delivery settings at runtime, and use the existing HTTPS reverse proxy. The image excludes local credentials, environment files, document/output directories and logs. For a non-container Debian/Ubuntu deployment install the same four packages and provide writable private temporary space. `VERA_OCR_LANGUAGES` defaults to `dan+eng`; only installed requested languages are used, with English fallback when available. macOS development can use Homebrew `tesseract` and `poppler`; production has no macOS API dependency.

Scanning is a bounded, read-only request: first three PDF pages, images scaled to 2000px when rendering PDF pages, at most two scans per Rails process, a 25-second total deadline and 12-second subprocess deadlines. Processes run without a shell and with one OCR thread. Temporary files are removed after success/failure; Ready staged OCR text/fields are retained in EP’s scoped enclosure-learning support table; sessions keep only the extraction UUID and logs omit document content. Unattached staged support expires with its upload; accepted support retains source-document/event links. Missing tools, unreadable documents and scanner saturation leave the attachment flow usable and offer Scan again. Results are heuristic, not certified invoice interpretation; verify against the preview. PDF/date scans interpret non-ISO numeric dates as day/month/year. Attachment acceptance may suggest a draft reference, current posting accounts and amounts for an empty row; review and explicitly save these choices. Background inference never rewrites saved or posted amounts.

## Enclosure learning worker

Apply the new EP migration with `mix ecto.migrate` and restart EP for the updated Oban cron configuration. The migration is already applied to this local development database. VERA requires no new daemon or business database. Existing EP projection workers process recalculation jobs after enclosure attachment and explicit row saves/posting; an Oban cron sweep queues each participating book every 15 minutes. Jobs process 100 support records at a time and continue with a cursor.

`finance_enclosure_learning` retains raw extraction/fields, SHA/digest, original/applied/latest proposals, algorithm/config/account versions, actual saved choices (including effective credit and VAT legs), and accepted event/identity/backend references. The classifier uses up to 200 current, explicitly confirmed supplier examples per book, preferring a normalized CVR/VAT identifier over supplier name. Unconfirmed auto-filled rows are not teaching examples. It falls back to unambiguous eligible expense/chart-name and bank candidates, leaves ambiguous accounts unset, and leaves foreign-currency amounts unset. No rates, conversions or accounts are created by inference.

Initial/applied proposals stay fixed; background runs change only best_guess. Accepted choices remain reconstructible from the linked accepted journal events, while original OCR/proposal annotations are protected document support data and must be included with artifact backups. Orphan staged records are removed by the existing upload cleanup worker; accepted support survives staging cleanup and retains book/row/document scope. Existing rows are not overwritten when another document is attached. The attachment dialog displays the latest proposal separately from the saved row.
