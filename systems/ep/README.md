# EP — Event Protocol

API-focused Elixir/Phoenix application for the shared Event Protocol. Module namespaces are `Ep` and `EpWeb`; the OTP application is `:ep`.

## Included

- Phoenix 1.8 with Bandit, JSON requests/responses and request telemetry.
- PostgreSQL/Ecto with UUID generator defaults and microsecond UTC timestamps.
- Supervised Oban database-backed jobs, an initial queue and its versioned migration.
- Separate development/test databases, environment URL overrides and ExUnit SQL sandbox support.
- `GET /health/live` for process liveness and `GET /health/ready` for migrated EP database/queue readiness.

The first EP vertical slice is implemented: email verification, opaque bearer sessions, idempotent `CreateTenant`, atomic first-admin/event/receipt/outbox persistence, durable local projection and authorized MV reads. Identity records are separate from event payloads; raw credentials never enter event or job payloads.

This is a local-development slice, not production-ready system 1. Production magic-link delivery remains disabled until a reviewed email adapter is configured. Phone/code/OpenID authentication, organizational delegation, occasion workflows, generic permission registration, source-level abuse controls, rights/erasure/backup automation and general subscriber fan-out remain planned. The current schema accepts global identity and tenant events only; occasion scope will add a parent-validated schema/migration. No public raw-event ingestion exists. Phoenix PubSub is not the durable outbox.

## Requirements

Use the versions pinned in `mise.toml` (Elixir 1.20 / Erlang OTP 29), plus PostgreSQL. Docker Compose provides PostgreSQL 17 locally; an existing PostgreSQL server also works through URL overrides. No Node.js/frontend asset toolchain is required.

## Local setup

From `systems/ep`:

```sh
mise install
mix deps.get
docker compose up -d --wait
mix ecto.setup
mix phx.server
```

The default local database is `ep_dev`, user/password `ep`, at `127.0.0.1:55432`. Compose binds only to loopback and uses these development-only credentials. Change `EP_POSTGRES_PORT` when needed and provide corresponding database URLs.

Using an existing server instead:

```sh
export DATABASE_URL=ecto://USER:PASS@HOST:PORT/ep_dev
export TEST_DATABASE_URL=ecto://USER:PASS@HOST:PORT/ep_test
mix ecto.setup
mix phx.server
```

The database user needs permission to create the development/test databases for the setup/test aliases, or those databases must already exist. `.env.example` documents variables; Phoenix does not automatically load `.env` files. Never point `TEST_DATABASE_URL` at a database containing application data.

```sh
curl http://localhost:4000/health/live
curl http://localhost:4000/health/ready
```

Expected responses: `{"status":"ok"}` and `{"status":"ready"}`. Readiness returns 503 with a generic unavailable status if its database/queue check fails. It does not certify business capability or load capacity.

## Checks

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix precommit
```

`mix test` creates/migrates the test database and isolates database work with the SQL sandbox. Oban uses manual test mode so queued jobs do not run implicitly. `mix precommit` checks compilation, dependency usage, formatting and tests.

## Production configuration

Provide `DATABASE_URL`, `SECRET_KEY_BASE` (generate with `mix phx.gen.secret`), `PHX_HOST` and `PHX_SERVER=true`; configure `PORT` and `POOL_SIZE` for the deployment. Terminate/configure TLS appropriately and run migrations before admitting traffic. Local Compose and development secret values are not production configuration. Replica count, pool sizes, load objectives, authorization, job recovery and deployment policies require validation before production.

## First operational flow

1. Request email verification:

   ```sh
   curl -sS -X POST http://localhost:4000/api/v1/auth/magic-links \
     -H 'Content-Type: application/json' \
     -d '{"email":"developer@example.test"}'
   ```

   Development delivery writes a private JSON message containing the email and verification token under `tmp/magic_links/`. Read the matching local file; this directory has no HTTP route and is ignored by Git. Treat its token as a credential and delete the message after use. Production has no default delivery adapter and returns 503 instead of exposing local credentials.

2. Verify the token by posting `{"token":"MAGIC_LINK_TOKEN"}` to `/api/v1/auth/magic-links/verify`. The response contains an opaque bearer token and expiry, with `Cache-Control: no-store`. Magic links expire in 15 minutes, are single-use, and a resend invalidates the earlier link. At most three sends per email are accepted per rolling 15 minutes; extra requests return the same generic 202. Sessions currently last 12 hours (configured through `:session_lifetime_seconds`), and current identity/session state controls access. The separate identity store currently implements verified human email signup only.

3. Create a tenant using the returned bearer token:

   ```sh
   curl -sS -X POST http://localhost:4000/api/v1/tenants \
     -H 'Content-Type: application/json' \
     -H 'Authorization: Bearer SESSION_TOKEN' \
     -H 'Idempotency-Key: create-my-tenant-1' \
     -d '{"name":"My camp organization"}'
   ```

   A new command returns 201 with `tenant_id`, `command_id`, two `event_ids` and `stream_version: 2`. Repeating the same identity/key/name returns 200 with the original result; changing the name under that key returns 409. Keys are 1–128 letters, digits or `._:-`. The server derives the actor from the authenticated session, never a body/header identity ID. Tenant creation does not create an occasion or occasion membership.

4. Query `GET /api/v1/tenants/TENANT_ID` using the bearer token. It returns 202 while the directory MV is pending and 200 with the name, source version and update time after the worker projects it. An unrelated identity gets 404 for both an existing tenant and an unknown ID. Current revoked access/identity/session and stopped MV controls override cached projected data.

## Transaction and projection boundaries

`Ep.Tenancy.create_tenant/3` validates the request and rechecks the current session inside its transaction. Identity-scoped command locks and a unique receipt prevent concurrent duplicate acceptance. It commits tenant state, first `tenant_admin` access, initial MV control, `TenantCreated` and `TenantAdminGranted` envelopes/details, stream head, receipt, two outbox rows and an Oban job together. No post-commit best-effort enqueue is required.

`Ep.Projections.TenantWorker` is the first local publisher/consumer implementation. It locks the tenant projection, reads committed pending outbox rows in stream order, and commits MV updates, per-event consumer inbox checkpoints and delivery acknowledgements atomically. A retry after completion does nothing. It does not scan by an unsafe global event-ID watermark. Unsupported event schemas fail the job and retain pending outbox work.

The first `tenant_admin` role currently authorizes the tenant-directory query; generic permission/delegation administration is not yet available. This demonstrates the first-admin grant without claiming the rest of the permission catalogue is implemented. The first MV control defaults to running. A stopped control blocks reads and snoozes ordinary projection work; the full lifecycle/configuration and mandatory privacy-cleanup workers remain to be implemented.

For recovery after discarded/deleted jobs:

```sh
mix ep.outbox.recover
```

The command requeues up to 100 tenants with pending rows. Repeat as necessary; duplicate wake-ups are safe. Oban retains failed job evidence and retries normal failures. Resolve the underlying failure before retrying a repeatedly failing schema or data case.

For an operator-only local rebuild in IEx:

```elixir
Ep.Projections.TenantDirectoryProjector.rebuild(tenant_id)
```

The rebuild transaction replays retained tenant events into this MV and replaces its inbox checkpoints without sending notifications, creating new events or re-enqueuing external effects. The public query still enforces current access/MV controls. **Erasure-aware replay is not yet implemented**, so this operator function must not be used for production personal-data restoration until the privacy registry is integrated.

## Verification and next delivery

Tests cover verified/single-use/expired links, session expiry/revocation/suspension, atomic rollback, retries and conflicts, two-connection concurrent duplicate commands, outbox retry/recovery, effect-free rebuild, actor spoof prevention, pending/ready HTTP responses and cross-tenant isolation. They do not establish the planned 40,000–80,000 concurrency capacity.

Occasion creation is available as described below. Next add governed administrator delegation and recruitment gating. Implement the production authentication/delivery and privacy lifecycle contracts before admitting production personal data. Reuse the transaction/outbox pattern rather than bypassing it with direct business-table or MV writes.

See [architecture](../../architecture.md), [datastore](../../suggested-data-store.md), [system 1 plan](../../system_1_plan.md) and [privacy requirements](../../gdpr.md).

## Occasion creation

Run `mix ecto.migrate` against your configured EP development database before using the new endpoints. Existing tenants are supported; their `occasion_directory` control is initialized on first creation without changing tenant grants.

- `POST /api/v1/tenants/:tenant_id/occasions`, with Bearer authentication and `Idempotency-Key`: `{ "name": "Spejdernes Lejr 2030", "slug": "sl2030", "expires_at": "2031-01-01T23:59:59.000000Z", "assign_self_as_admin": true }`.
- `GET /api/v1/tenants/:tenant_id/occasions`: access-filtered tenant-admin directory, 202 while pending, otherwise 200. Empty lists are valid before first creation.
- `GET /api/v1/tenants/:tenant_id/occasions/:id`: tenant admin or an active admin of this exact occasion, 202 pending / 200 ready. Foreign parent, absent resources and denied access return 404.

Creation requires current active tenant-admin authority in an active tenant. Name is trimmed to 1–120 characters; slug is 1–64 lowercase ASCII letters/digits with internal hyphens and unique within the tenant. Expiry must be a future ISO8601 timestamp. `assign_self_as_admin` is an optional boolean, default false in EP; TOM offers it as a checked, explicit option. Client-supplied lifecycle, recruitment state, actor and other grants are ignored. No participant membership is created.

Acceptance atomically records the parent-bound occasion guard, `OccasionCreated`, optional self `OccasionAdminGranted` and its synchronous grant, stream head, receipt, outbox and Oban wakeup. New occasions are drafts with recruitment closed. The scope key is `tenant:TENANT_ID:occasion:OCCASION_ID`; composite foreign keys reject mismatched event/grant/view parents. Command fingerprints include the tenant binding. Slug and command locks serialize competing creates; an identical receipt is replayed, a changed command conflicts, and a duplicate slug under another command returns `slug_taken` (409).

`OccasionWorker` projects only occasion streams; `TenantWorker` projects only tenant streams. Independent controls prevent a stopped occasion directory from blocking tenant projection. The occasion projector orders by stream and version and atomically commits output, inbox and acknowledgment. `mix ep.outbox.recover` routes pending work to the corresponding worker. These local consumers do not implement generic external fan-out.

The expiry is a recorded **review deadline**, not automatic deletion or retirement. Expiry-review task scheduling, retirement/erasure execution, participant recruitment, occasion editing, assignment of other admins and occasion replay/rebuild are subsequent work. Do not treat this slice as production retention compliance. Admin grants remain separate from the one-membership-per-identity-per-occasion rule.
