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

Each command creates a new machine identity without a login channel, session or administrative grants, and prints a **non-secret source UUID**. Keep source scope/actor/backend immutable. Prefer the governed source registration/revocation APIs below and TOM settings; the bootstrap command is for trusted operator use. Do not create sources dynamically from a user's request or infer reporting authority from an occasion ID in a URL.

`X-EP-Backend-Token` authenticates ingestion and catalogue requests. The source must belong to that authenticated backend, remain active, have an active actor, and reference an active tenant and a draft/active occasion where applicable. A backend can report for a provisioned source without a user's session, allowing it to capture failed/unauthenticated requests. This does not grant monitoring reads or permission to act as the initiating user. Global sources cannot be read through tenant APIs; explicit `platform_monitor` permission is required for the separate platform endpoints.

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

Tenant admins can read/action operational monitoring in their tenant. Occasion admins must supply their exact `occasion_id` for lists and can read/action only issues in that occasion. No tenant-wide counts or sibling records leak into an occasion query. Foreign, revoked and inaccessible records return the same 404. Tenant/occasion lifecycle and current grants are checked on every request. Restricted diagnostics additionally require an explicit `diagnostics` grant for the exact scope; tenant administration alone never grants it.

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

The initial grouping is deliberately coarse: **source + catalogue code**, with first/last receipt time, occurrence count and current owner/state. This separates tenant/occasion scope through the source, without serializing business streams. A new observation for a resolved issue emits a reopen fact. Information-level observations also have a grouped issue row; clients filter severity/state to construct their default operational view. Grouping remains source + code; alert rules separately support aggregation windows and cooldowns. Escalation and custom fingerprints remain extensions.

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

## Source administration, alerts and restricted operations

All routes below use JSON and `Cache-Control: no-store`. `X-EP-Backend-Token` authenticates backend-only routes; ordinary administration uses the current user's Bearer session. Source IDs never authorize reads. Every mutation of source/rule configuration requires `Idempotency-Key`; state/suppression also require the current rule `expected_version`.

| Route | Purpose |
|---|---|
| `GET /api/v1/monitoring/bindings` | Backend-only `{sources: {scope_key: source_uuid}}` for that backend's active reporting sources; no user data. |
| `GET /api/v1/me/monitoring-access` | Current user's explicit `platform_monitor` capability. |
| `GET/POST ROOT/sources` | List sources plus approved backend IDs; register with `{backend_id, occasion_id?}`. Registration reuses an active binding; source actor is a channel-less machine identity. |
| `POST ROOT/sources/:id/revoke` | Governed revocation; ingestion rechecks current status. |
| `GET ROOT/assignees?occasion_id=...` | Current eligible scope administrators as `{identity_id,label}`; no arbitrary identity directory. |
| `GET/POST ROOT/rules` | List or create a rule using the schema below. |
| `POST ROOT/rules/:id/state` | `{enabled, expected_version}`; append governed configuration fact. |
| `POST ROOT/rules/:id/suppression` | `{expected_version, reason, until}`; reason `maintenance` or `investigation`, future UTC time at most 24 hours. Observation capture continues. |
| `GET ROOT/alerts` | Latest 100 scoped alert outcomes, including unknown/cancelled; no delivery addresses. |
| `GET ROOT/observations/:id/diagnostic` | Current scope authority **plus** exact-scope diagnostics grant; structured trace only, unavailable after 30 days/erasure. |
| `POST /api/v1/monitoring/alerts/claim` | Delivery backend only, `{request_id: UUID}`. At most one intent with attempt ID, safe summary, scope and current verified recipient emails. This protected response is delivery material, not a public event payload. |
| `POST /api/v1/monitoring/alerts/:id/outcome` | Same bound delivery backend, `{attempt_id,status}`; terminal outcome is idempotent and never resends. |

`ROOT` is `/api/v1/tenants/:tenant_id/monitoring` or `/api/v1/monitoring/platform`. The latter requires explicit global `platform_monitor`; it also exposes the existing issue/observation/timeline/detail/action operations for global records. Tenant administrators gain no platform access. Configuration/suppression/revocation append facts in `event`/`event_details`; supporting tables enforce current control and work-claim state.

Rule creation: `{source_id, code, threshold, window_seconds, cooldown_seconds, enabled, recipient_ids, delivery_backend_id}`. Code must be in the approved catalogue; threshold 1–10,000, window 60–3,600 seconds, cooldown 60–86,400 seconds, 1–10 currently eligible recipients, approved delivery backend. Evaluation occurs on new ingestion, not projection replay. Only new occurrence facts inside the window count. Claims recheck rule/source/recipient authority. A claim is leased for 300 seconds; expired claims become `unknown` and are never automatically resent. Repeating the same request UUID during its lease returns the same material. Outcomes are `test_accepted`, `provider_accepted`, `rejected` or `unknown`. Provider acceptance is not delivery confirmation.

Optional observation `diagnostic` is `{exception_class, frames: [{file, label, line}]}` (maximum 10 frames). Only bounded class/label/file-basename tokens and integer line numbers are accepted; raw exception messages, local variables, full paths and arguments are forbidden. Ordinary monitoring views omit diagnostics.

## Local operational implementation and remaining deployment work

The [independent collector and runbook](../../monitor/README.md) implement encrypted bounded spooling, probes, local loss/quarantine accounting, backend draining and isolated backup rehearsal. EP's optional telemetry observer aggregates request/database/job/projection breaches without database work inside telemetry callbacks. Startup/periodic publication recovery requeues pending facts; Oban rescues jobs orphaned by process termination. Replaying projections creates no notifications.

Monitoring erasure uses an HMAC subject index, durable suppression ledger, detail/metadata redaction and late-backlog filtering. Reads fail closed during pending monitoring cleanup; business requests remain independent. Opt-in maintenance enforces the implemented 30/90-day defaults; approved retention/hold policies remain pending. Snapshot-consistent encrypted backup manifests and signed erasure worklists are implemented for local rehearsals. Restore cleanup covers monitoring only, keeps the sandbox unpublished, and never retires original/offline media automatically.

Production hosts, independent paging/provider callbacks, on-call ownership, domain-wide erasure adapters, legal holds, offline/immutable backup custody, real-browser verification and representative capacity testing remain in [pending_details.md](../../../pending_details.md). This API does not expose WebSocket/SSE subscriptions; clients stream their own authorized view updates. Local test evidence is in [local_rehearsal.md](../../monitor/local_rehearsal.md).
