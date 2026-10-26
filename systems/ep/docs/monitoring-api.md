# Monitoring API v1

Machine-readable contract: [OpenAPI 3.1](monitoring-openapi.json).

Implemented backend foundation for [the monitoring plan](../../../monitoring_plan.md). EP persists observations and lifecycle facts in `event`/`event_details`, with a dedicated transactional `monitoring_pending` publication table, Oban `monitoring` queue and incrementally maintained `monitoring_view`. TOM and other clients use JSON only; a client can translate these results into Turbo Streams, LiveView or another in-context presentation.

## Onboarding and credentials

Run migrations first. Provision a separate backend credential for each application. `EP_BACKEND_ID`/`EP_BACKEND_TOKEN` retain their existing single-backend behavior; `EP_BACKEND_TOKENS_JSON` optionally supplies an object mapping additional backend IDs to independent secrets of at least 32 characters. Store it in deployment secrets, never source control. JSON entries override matching single-backend entries. Tests use their own fixed credential configuration.

As an operator, register each permitted reporting scope:

```sh
mix ep.monitoring.source tom TENANT_UUID
mix ep.monitoring.source tom TENANT_UUID OCCASION_UUID
mix ep.monitoring.source ep global
```

Each command creates a new machine identity without a login channel, session or administrative grants, and prints a **non-secret source UUID**. Keep source scope/actor/backend immutable; revoke reporting by setting `monitoring_source.status` to `revoked` through an operator-controlled database change. Source lifecycle administration and its operator audit UI are future work. Do not create sources dynamically from a user's request or infer reporting authority from an occasion ID in a URL.

`X-EP-Backend-Token` authenticates ingestion and catalogue requests. The source must belong to that authenticated backend, remain active, have an active actor, and reference an active tenant and a draft/active occasion where applicable. A backend can report for a provisioned source without a user's session, allowing it to capture failed/unauthenticated requests. This does not grant monitoring reads or permission to act as the initiating user. Global sources cannot be read through tenant APIs; a separate platform-operator permission surface is not implemented yet.

## Endpoints

| Method/path | Authorization | Result |
|---|---|---|
| `GET /api/v1/monitoring/catalogue` | Backend token | Schema version and approved codes with safe messages, severity/category/outcome. |
| `POST /api/v1/monitoring/observations` | Backend token + registered source | Persist a validated observation; 201 new / 200 identical replay. |
| `POST /api/v1/monitoring/delivery-outcomes` | Same | Delivery-only vocabulary; delivery-attempt UUID required. |
| `GET /api/v1/tenants/:tenant_id/monitoring/issues` | Current user Bearer | Scoped issue MV list. |
| `GET /api/v1/tenants/:tenant_id/monitoring/observations` | Current user Bearer | Scoped observation MV list. |
| `GET /api/v1/tenants/:tenant_id/monitoring/timeline` | Current user Bearer | Observation and lifecycle entries, optionally filtered by `issue_id`. |
| `GET /api/v1/tenants/:tenant_id/monitoring/issues/:id` | Current user Bearer | Current MV row and authoritative expected version, or 202 pending before first projection. |
| `POST /api/v1/tenants/:tenant_id/monitoring/issues/:id/actions` | Current user Bearer + idempotency key | Accept an operator action with expected version; no external retry side effect. |
| `GET /api/v1/me/commands/:id` | Current user Bearer | Private accepted receipt or `unknown`. |
| `GET /api/v1/me/commands?command_type=TYPE&idempotency_key=KEY` | Current user Bearer | Reconcile when the original command response, including its ID, was lost. |

Tenant admins can read/action operational monitoring in their tenant. Occasion admins must supply their exact `occasion_id` for lists and can read/action only issues in that occasion. No tenant-wide counts or sibling records leak into an occasion query. Foreign, revoked and inaccessible records return the same 404. Tenant/occasion lifecycle and current grants are checked on every request. No restricted security/raw-diagnostic catalogue or admin permission to read such material is introduced by this slice.

## Record an observation

```json
{
  "source_id": "00000000-0000-4000-8000-000000000001",
  "source_observation_id": "00000000-0000-4000-8000-000000000002",
  "code": "application.exception",
  "correlation_id": "00000000-0000-4000-8000-000000000003",
  "observed_at": "2026-10-23T10:00:00Z",
  "occurrence_count": 1,
  "duration_ms": 123,
  "related": {
    "business_command_id": "00000000-0000-4000-8000-000000000004"
  }
}
```

Required: source UUID, stable source-observation UUID, catalogue code, correlation UUID, UTC observed time. Optional: occurrence count 1–10,000 (default 1), duration 0–86,400,000 milliseconds, `related` map of UUID references named `business_command_id`, `event_id`, `delivery_attempt_id`, `job_id`. Observed time must be within 30 days of receipt, allowing bounded offline capture. EP sets receipt time, application, actor, scope, safe text, severity, category and outcome. Unknown fields, raw messages, traces, email addresses, tokens, caller-assigned roles/scope and arbitrary event types are rejected. References are **source-reported opaque links**, not proof that EP accepted the referenced business operation; resolve them through independently authorized APIs.

Use the same source-observation UUID and normalized content when transport is uncertain. Same source/UUID/content returns the original command/events without recounting or emitting another job. Changed content returns 409 `idempotency_conflict`. Deduplication precedes rate counting: at most 600 new observations per source per rolling minute; repetitive outcomes can use occurrence counts. A 429 means the client must back off and use bounded collection with explicit loss accounting. EP does not promise lossless telemetry storage.

Example acceptance:

```json
{
  "issue_id": "uuid",
  "command_id": "uuid",
  "event_ids": ["uuid", "uuid"],
  "stream_version": 2,
  "correlation_id": "source-correlation-uuid",
  "replayed": false
}
```

The initial grouping is deliberately coarse: **source + catalogue code**, with first/last receipt time, occurrence count and current owner/state. This separates tenant/occasion scope through the source, without serializing business streams. A new observation for a resolved issue emits a reopen fact. Information-level observations also have a grouped issue row; clients filter severity/state to construct their default operational view. Configurable fingerprints, source component/release metadata, escalation and aggregation windows remain future extensions.

Delivery codes are `delivery.attempted`, `delivery.provider_accepted`, `delivery.delivered`, `delivery.bounced`, `delivery.rejected`, `delivery.unknown`. Every delivery report requires `related.delivery_attempt_id`. Reports become `DeliveryOutcomeRecorded` facts, preserve their source, and never redeem a challenge, grant a role or send a message. They describe what the authenticated application **reports**; the application is responsible for validating provider callbacks. EP does not independently verify inbox delivery. Different stage codes remain separate observations, linked through the attempt/correlation references; no authoritative delivery workflow state machine is implied.

## Lists, freshness and timeline

All lists accept optional `occasion_id`, `issue_id`, `code`, `severity`, `state`, `application`, `correlation_id`, `limit`, `cursor`, `cutoff`. Limit defaults to 50 and is capped at 100. The current order is descending projection insertion time and UUID, suitable for a stable paginated snapshot; clients can render severity labels and filter unresolved warnings/errors. Severity-ranked server sorting, time-range filters and live list subscriptions remain extensions.

Response: `items`, `next_cursor`, `cutoff`, `freshness`. Each item has `id`, `issue_id`, `occasion_id`, `source_version`, `updated_at`, `data`. Treat the opaque cursor as transport state; carry the same filters when paging. The cutoff fixes the insertion horizon, not a historical snapshot of mutable issue contents. Fetch fresh pages to see newly arrived issues; do not reorder a user's current list unexpectedly.

Freshness includes `checked_at`, scoped `pending_events` and `oldest_pending_at` (null when none). An empty list with pending events is not evidence of no issues. Issue detail additionally returns `expected_version` and `status: ready|pending`. A projected but behind row returns 202 with `Retry-After: 1`; the caller can keep the existing view visible while reconciling. Use `/timeline?issue_id=...` to inspect paginated safe observations and lifecycle entries; descending order means latest first. Domain command receipts are queried separately, not silently merged across access boundaries.

`mv_control` name `monitoring` governs tenant monitoring serving and processing. A stopped control returns 503 `view_stopped` and snoozes projection jobs; ingestion still records facts durably. Global processing has its separate restricted scope, without a tenant control. The consumer locks per issue, verifies contiguous versions, updates the MV and acknowledges pending records atomically. A batch processes at most 1,000 facts and schedules continuation. Duplicate jobs do not duplicate entries. `mix ep.monitoring.recover` requeues retained pending streams, including those whose jobs exhausted. It does not reconstruct erased/missing source history or execute external actions.

## Issue actions

Send `Idempotency-Key` and one exact payload shape:

```json
{"action":"acknowledge","expected_version":2}
```

Other shapes are `{"action":"assign","expected_version":3,"owner_identity_id":"uuid"}`, `{"action":"resolve","expected_version":4,"reason":"corrected"}`, and `{"action":"reopen","expected_version":5}`. Resolution reasons are `corrected`, `duplicate`, `accepted_risk`. Owner must have a current administrative grant in the issue's tenant/occasion. Free-text notes and unrelated fields are not accepted. The result returns accepted event/command IDs and stream version before asynchronous projection; identical retries return the original result. Stale versions return 409 `version_conflict`. Acknowledgment/closure changes administrative state; it does not prove recovery or retry any business operation.

## Correlation and reconciliation for in-context feedback

Supply a UUID in `X-Correlation-ID` on EP calls; EP returns a canonical UUID in the same response header and propagates it to accepted business events. Invalid/missing headers get a generated UUID. Monitoring observations retain their explicit originating correlation ID, independently of their ingestion request header. Correlation conveys no authority, uniqueness or idempotency guarantee.

When TOM fails after a possible EP acceptance, keep the user's view/form and show an inline pending/error message. Query the original user's command receipt by known ID or **original command type + idempotency key**. `accepted` returns the persisted receipt result, never raw delivery material; `unknown` means no visible accepted receipt was found at query time, **not failed or safe to repeat**. The command may still be in flight. Only the receipt owner can reconcile; tenant/occasion-bound results also require current administrative context. Participant-only receipts therefore need a future purpose-specific ownership policy before this generic endpoint can expose them. Challenges/auth issuance without command receipts cannot be reconciled through this API; use their existing explicit reissuance semantics.

An unexpected EP router failure returns JSON 500 `{"error":"internal_error","correlation_id":"uuid","outcome":"unknown"}` with no-store and the correlation response header. It does not assert the command rolled back. The boundary emits a safe local error marker; if `EP_MONITORING_SOURCE_ID` names an active `ep` source, it attempts bounded internal observation capture after transaction rollback. Failures in monitoring routes do not recursively ingest more failures. Normal HTTP exceptions retain framework handling. Failures before router dispatch, process/node termination and database outages still require independent logs/probes/collection; a stream cannot be promised from a dead process.

All monitoring/reconciliation responses are no-store. Missing backend credential: 401 (503 if backend credentials are unconfigured). Missing/expired user session: 401. Invalid input: 422. Inaccessible source/issue/context: 404. Conflicting retry/version: 409. Stopped MV: 503. Source rate limit: 429. A caller must inspect outcome/status, not infer business failure from a transport error.

## Deliberate remaining work

This contract is the backend foundation, not completion of the full monitoring plan. TOM now implements [initial instrumentation, scoped monitoring screens and native Turbo feedback with safe form preservation](../../tom/docs/monitoring.md). Independent outage probes/collector/spooling, automatic infrastructure/job telemetry capture, alert rules/executors/suppressions, restricted platform/security read permissions, trace artifacts, source lifecycle administration, configurable grouping, retention/erasure automation and backup sanitation still require implementation. Existing framework telemetry is not automatically persisted by this change. The endpoint does not provide WebSocket/SSE subscriptions; clients can perform bounded authorized status queries and stream their own view updates.

Do not claim production readiness: loss/overload behavior, retention schedules, restore sanitation and peak-load service targets require the planned operational rehearsals. In particular, the new monitoring tables contain identifying references and must be included in future erasure and backup indexing.
