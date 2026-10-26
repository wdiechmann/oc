# EP — Event Protocol

EP is the Elixir/Phoenix JSON API and PostgreSQL-backed authority for identities, invitations, tenants, occasions, recruitment, scoped events and projections. It does not send email/SMS, construct application links or expose a filesystem mailbox to clients. API responses are the delivery handoff; future MCP operations must preserve the same security and lifecycle contract.

## Run locally

Use the Elixir/Erlang versions in `mise.toml` and an existing PostgreSQL server or the optional compose service. From `systems/ep`:

```sh
export DATABASE_URL="ecto://$(whoami)@localhost:5432/sl2030_ep_dev"
mix ecto.setup
mix phx.server
```

`GET /health/live` is liveness. `/health/ready` checks required tables and Oban. Backend credentials must be provisioned before issuing authentication challenges or invitation delivery responses. This workspace already has separate private development credentials in EP and TOM. For a fresh checkout run `systems/tom/bin/provision-ep-backend`; this operator command creates matching mode-0600 files at `systems/ep/config/backend_api_token` and `systems/tom/config/ep_backend_token`, both gitignored. Each running app reads only its own configuration file. These are configuration secrets, not a shared runtime integration.

Production uses operator-provided `EP_BACKEND_TOKEN` (at least 32 characters), `EP_BACKEND_ID` (default `tom`), `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST` and `PHX_SERVER`. No development secret file is read in production. The backend-token map is the first trusted-caller gate, not the complete planned application registry/permission system.

## Authentication API and delivery contract

The calling backend sends `X-EP-Backend-Token` to both POST `/api/v1/auth/magic-links` and POST `/api/v1/auth/magic-links/verify`. Missing/wrong credentials fail closed. The backend token never belongs in browser JavaScript, HTML or user messages.

Issuance accepts `{ "email": "person@example.org" }` and returns 202 with:

```json
{"status":"check_your_email","delivery":{"email":"person@example.org","token":"SINGLE_USE_SECRET","expires_at":"ISO8601_TIMESTAMP"}}
```

The application renders/sends its own message and exposes only a generic check-email response to the browser. At the email limit, the authorized API gets the same status with `delivery: null`; TOM sends nothing and keeps the browser response generic. This applies equally to new and existing addresses. No message provider is called by EP and no raw secret enters EP event details, command receipts or jobs. Only a hash is stored.

A challenge is valid for 15 minutes, single-use and bound to the issuing backend. Explicit new issuance invalidates outstanding challenges for that email/backend. Three requests per email in a rolling 15-minute window are currently allowed. Issuance is an explicit fresh-challenge operation, not a replayable secret response: after a lost response or failed delivery, request a new challenge; clients must not silently retry issuance. Requests from other backends do not consume an existing backend's challenge. Production source-level abuse controls remain planned.

Verification accepts `{ "token": "SINGLE_USE_SECRET" }` under the same backend credential and returns an opaque Bearer session and expiry. It verifies or creates the same canonical identity; subsequent sign-ins do not create memberships or repeat admin grants. Current identity/session revocation and expiry are checked on protected operations. The application must not redeem links on GET (mail scanners may follow links). TOM stages the secret privately in its encrypted session, redirects off the token URL and requires an explicit CSRF-protected confirmation POST. Password auth is excluded; phone/code/OpenID/recovery remain future work.

## Invitations

Tenant-admin and occasion-admin creation require both current tenant-admin Bearer authority and the backend credential. EP returns ordinary command metadata plus `delivery`: recipient email, role, tenant/occasion IDs and names, invitation ID and expiry. TOM renders and sends the message linking to its own `/invitations` page. The invitation itself is not a login credential: recipients must verify their email, then explicitly accept.

- GET/POST `/api/v1/tenants/:tenant_id/admin-invitations`.
- GET/POST `/api/v1/tenants/:tenant_id/occasions/:occasion_id/admin-invitations`.
- POST on a collection's `/:id/accept` and `/:id/revoke` routes.
- GET `/api/v1/me/tenant-admin-invitations` and `/api/v1/me/occasion-admin-invitations`.

Writes require Idempotency-Key. Invitations expire after seven days and may be revoked while pending. Acceptance rechecks verified recipient, parent lifecycle and sponsor authority. Tenant invitations grant TenantAccess; occasion invitations grant only the named occasion's admin role, not tenant access or participant membership. Occasion admins cannot appoint further admins without separate tenant authority. Scope-specific row/command/grant locks protect retries and acceptance/revocation races.

For a lost response or caller delivery failure, retry invitation creation with the same key and payload. EP returns the same invitation and newly reads its current delivery material without creating a second invitation. Delivery material is not stored in the command receipt. If the invitation is no longer eligible, `delivery` is null. SMTP retry can duplicate an already accepted message; applications must not claim exactly-once email delivery. Revoking an invitation never removes an already accepted admin grant. Subsequent sign-in never reinstates a revoked grant.

The migration cancels obsolete queued `Ep.Invitations.DeliveryWorker` jobs. That worker and EP's magic-link/invitation mailbox adapters are removed. Legacy EP mailbox files are not used by either application; old magic links lacking the new backend binding must be replaced with newly requested links. Stop/restart EP when upgrading.

## Tenants, occasions and returning admins

- POST `/api/v1/tenants`: verified identity creates a tenant and its first tenant_admin atomically.
- GET `/api/v1/tenants/:id`: current authorized tenant directory query.
- POST/GET `/api/v1/tenants/:tenant_id/occasions`; GET its `/:id`.
- GET `/api/v1/me/workspaces`: current identity's authorized tenant and occasion navigation from running projections, filtered by current grants and parent lifecycle. It restores navigation after a new session without trusting roles stored in a browser cookie.

Tenant and occasion writes accept Idempotency-Key. Occasions require name, tenant-local slug and future expiry review timestamp, and start as draft/recruitment closed. Optional self occasion-admin assignment is explicit; it creates no participant membership. Composite keys reject mismatched tenant/occasion parents. Queries return pending while projections catch up; stopped controls and current authority override projected content. The physical invitation table retains its original name `tenant_admin_invitation`, with nullable occasion scope for additive compatibility.

## Recruitment

Current tenant/occasion admins manage GET `/api/v1/tenants/:tenant_id/occasions/:occasion_id/recruitment`, POST `/open` (title, instructions, published HTTPS privacy-notice URL, confirm_manual_review) and POST `/close` (reason). Public GET `/api/v1/recruitment/:tenant_id/:slug` serves only published MV-backed policy after authoritative open/expiry/control checks. Policy changes require explicit close/open.

Verified applicants POST `/api/v1/tenants/:tenant_id/occasions/:occasion_id/recruitment/applications` with notice_version and acknowledge_notice. One pending-only application per identity/occasion is enforced. Current admins GET that collection for up to 100 recent pending applications. A submission grants no membership, appointment or admin role. Shared occasion-row locks on submission serialize against exclusive close/open transitions. Changed policy and expiry block intake independently of MV lag.

Admission decisions, lead-vouch evidence, qualification/safeguarding integrations, applicant withdrawal/history, expiry WorkItems and privacy cleanup remain future work. Opening a local expression-of-interest form does not satisfy all production readiness/legal requirements.

## Event persistence and operations

Accepted business commands atomically persist current guards, scoped event/event_details, stream head, command receipt, outbox and projection job. Oban maintains tenant/occasion MVs with inbox deduplication and transactional acknowledgment. It remains responsible for these EP duties, not user-facing message transport. Consumers use committed pending state rather than a global sequence-ID watermark. Unknown schemas fail without acknowledging work.

`mix ep.outbox.recover` requeues pending projection work. `Ep.Projections.TenantDirectoryProjector.rebuild(tenant_id)` is operator-only and creates no external effects; erasure-aware replay is not implemented, so do not use it for production personal-data restoration. Occasion rebuild, generic fan-out/application registration, permission administration, admin removal/last-admin recovery, erasure/backup automation and load validation remain planned. No 40,000–80,000 concurrency claim has been validated.

## Verification

```sh
export TEST_DATABASE_URL="ecto://$(whoami)@localhost:5432/sl2030_ep_test"
mix precommit
```

Tests include backend-only issuance, backend-bound single-use verification, all seven signup/admin invitation/sign-in flows, preserved canonical identity/grants, no delivery jobs/material in events or receipts, current scoped navigation, idempotency, projection failures, and independent-connection invite/close/intake races. This is still a development slice, not a production security/privacy compliance claim.

## Monitoring backend API

EP now accepts scope-bound monitoring observations and delivery reports, persists them in
`event`/`event_details`, and serves authorized near-real-time issue/observation/timeline
views. Operator actions use expected versions and idempotency; private command receipts
support reconciliation after a client error. See [Monitoring API v1](docs/monitoring-api.md)
for source provisioning, credentials, routes, JSON examples, freshness and current limits.
Run `mix ecto.migrate` and restart EP before integrating clients. TOM UI/instrumentation,
independent probes, alert delivery and retention automation remain separate work.

## Local monitoring operations

The [monitoring API](docs/monitoring-api.md) now includes governed source administration, alert rules/claims/outcomes, explicit platform access and restricted diagnostics. Apply migrations before starting the new code. EP telemetry and retention are opt-in; an independent collector is required for durable outage visibility. See [operational runbook](../monitor/README.md), [local evidence](../monitor/local_rehearsal.md) and [pending deployment decisions](../../pending_details.md). Monitoring cleanup/restore does not yet erase all business-domain or third-party data.
