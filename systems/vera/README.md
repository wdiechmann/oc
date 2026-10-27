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

The initial scaffold includes Phlex/Tailwind UI, locally served Turbo, restrictive content policy, filtered parameters, health checks and an EP transport foundation. **Sign-in, tenant selection, books, financial commands and monitoring ingestion are next work; the landing page deliberately offers no live financial operations.** No EP records, grants or application credentials are created by setup.

Future authenticated calls must use a separately provisioned backend ID `vera`/credential accepted by EP and the current user's EP authorization. Do not reuse TOM's backend token or read TOM's files/session. VERA's own eventual credential file (`config/ep_backend_token`) is ignored; no credential is needed for today's public EP readiness check. EP remains authoritative for business changes, protected financial state and background MVs. File/object artifacts and external execution integrations follow explicit API contracts rather than a local business ledger.

## Verification

```sh
bin/rails test
bundle exec rubocop --cache false
bin/rails zeitwerk:check
bundle exec brakeman --no-pager
```

Tests block real network connections and cover the landing page, database-free boot, dependency outage, malformed readiness responses, fixed-origin validation and redirect refusal. Tailwind is built as part of Rails tests. Browser verification uses Playwright.
