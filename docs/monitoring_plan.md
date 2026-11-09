# Monitoring plan

## Purpose and status

Monitor code failures, infrastructure, user input, user-visible results, message delivery and asynchronous processing across EP, TOM and subsequent applications. Persist governed monitoring observations and their lifecycle as facts in EP's existing **`event` and `event_details` tables**. TOM provides an authorized, searchable list with drill-down into those facts through EP APIs; it has no monitoring database of its own.

This plan distinguishes the implemented monitoring foundation from the remaining operational requirements. It builds on [architecture.md](architecture.md), [suggested-data-store.md](suggested-data-store.md), [system_1_plan.md](system_1_plan.md), [gdpr.md](gdpr.md) and [TOM's architecture](../systems/tom/docs/architecture.md). The existing table is singular `event`; no parallel `events` table is proposed. An occasion remains the camp context, never an alternative name for a protocol event.

Existing foundations now include EP's initial [monitoring backend API](../systems/ep/docs/monitoring-api.md): registered sources, safe catalogue-based observations/delivery reports in `event`/`event_details`, dedicated incremental monitoring projections, scoped list/detail/timeline APIs, versioned issue actions, correlation headers and private accepted-command reconciliation. EP also has a safe router-failure boundary with optional internal capture. This implements the first backend slice, not all requirements below: TOM now implements [capture, scoped list/detail/timeline/action screens and in-context Turbo feedback](../systems/tom/docs/monitoring.md), with bounded command-status checks and operator-provisioned reporting sources. Independent collection/probes, richer diagnostics, alert execution, source administration and retention/erasure automation remain to be built. See the API document for precise current limitations and payloads.

## What is monitored

| Area | Capture | Interpretation and user response |
|---|---|---|
| Code and releases | Unhandled exceptions, failed invariants, contract/schema violations, release/build identifier and sanitized stack frames | Unexpected failures are errors. Give the user a safe explanation and support reference; retain diagnostic context for authorized operators. |
| Infrastructure | EP/TOM availability, database connection failures, pool pressure, latency, timeout rates, resource saturation | Assess sustained thresholds and missing signals. A healthy HTTP process does not prove database, delivery or projection health. |
| User input | Validation rejection, stale policy/version, conflict, expired challenge, throttling and authorization denial | Ordinary invalid input is an expected outcome, generally informational. Explain the correction beside the field or action and preserve safe entered values. Suspicious repetition or abnormal rates can become warnings/security alerts. |
| User output | EP accepted/rejected/pending result, TOM rendering/response failure and stale projection response | Distinguish accepted writes from pending views. Record a failed response after acceptance without claiming the write failed; reconcile using its command/idempotency reference. |
| Authentication and security | Invalid/expired verification, denied scope, revoked credentials, recovery actions and unusual failure rates | Keep security evidence restricted. Public responses must preserve anti-enumeration and avoid disclosing whether an identity exists. |
| Message delivery | Material returned, send attempted, provider accepted, provider rejected, delivery unknown, delivered/bounced where provider evidence exists | EP acceptance is not sending; provider acceptance is not inbox delivery. TOM owns delivery and reports observations to EP through an optional explicit API capability. |
| Queues and jobs | Waiting age, attempts, retries, exhausted jobs, quarantine and recovery actions | A retry is not automatically an incident. Escalate sustained delay, exhaustion or loss of progress; link the affected operation. |
| Materialized views | Oldest unprocessed committed outbox age, processing lag, stream gaps, projector failure, stopped control and last successful update | A stopped view is deliberately unavailable. A recent update timestamp alone does not prove catch-up. Show freshness and checkpoints. |
| Integrations and imports | Backend availability, malformed responses, reconciliation conflicts, uncertain external effects and import review backlog | Preserve source provenance and reconciliation ownership. Never blindly retry an external side effect after an ambiguous timeout. |
| Governance | Monitoring access, exports, acknowledgment, assignment, resolution, suppression changes and retention/erasure progress | Record consequential operator actions as facts. Resolve an incident without deleting its history or silently asserting the underlying condition recovered. |

Use levels `info`, `warning`, `error`, `critical` separately from outcome (`accepted`, `rejected`, `pending`, `failed`, `unknown`) and category. An HTTP 4xx is not inherently a software error. Acknowledgment, resolution and actual recovery are separate states.

## Persistence through the Event Protocol

### Observations are facts, not arbitrary log uploads

Add bounded commands such as `RecordMonitoringObservation`, `RecordDeliveryOutcome`, `AcknowledgeMonitoringIssue`, `AssignMonitoringIssue`, `ResolveMonitoringIssue` and `ChangeMonitoringRule`. EP validates schema, source authority, scope, payload size, allowed codes and idempotency before appending accepted facts. Applications cannot submit arbitrary event types or impersonate an actor.

Suggested event vocabulary:

- `MonitoringObservationRecorded`: an occurrence or bounded aggregate, including expected outcomes when useful.
- `MonitoringIssueOpened`, `MonitoringIssueEscalated`, `MonitoringIssueAcknowledged`, `MonitoringIssueAssigned`, `MonitoringIssueResolved`, `MonitoringIssueReopened`: issue lifecycle.
- `MonitoringConditionRecovered`: observed technical recovery, independent of an operator closing work.
- `DeliveryOutcomeRecorded`: the application's bounded report of a delivery attempt or verified provider notification.
- `MonitoringAlertRequested`, `MonitoringAlertOutcomeRecorded`: alert side effects and their results.
- `MonitoringRuleChanged`, `MonitoringSuppressionChanged`, `MonitoringExportRequested`: governed operational actions.

Business events remain business facts. A rejected command does not emit the business fact it failed to establish; it may produce a separate monitoring observation. Do not duplicate every existing successful domain event as a monitoring event merely to display a timeline: authorized projections can reference the existing fact.

### Split between envelope and details

Reuse existing envelope fields and the one-to-one `event_details.payload` map. Do not add an unbounded collection of diagnostic columns to `event`.

| Location | Proposed content |
|---|---|
| `event` | Existing ID, scope/key, tenant/occasion IDs, monitoring stream type/ID/version, event type/schema version, authenticated actor, monitoring command ID, correlation ID and insertion timestamps. |
| `event_details` | Stable code, severity, category, outcome, safe message/template parameters, originating application/component/release, source observation ID, observed time, received time, occurrence count/window, fingerprint, issue ID, causation and related business command/event/job references, bounded sanitized diagnostic fields and retention classification. |
| Protected optional artifact store | Large sanitized traces or evidence only when needed, with independently authorized references, expiry and deletion. No unrestricted dump linked from ordinary monitoring lists. |
| Supporting transactional tables | Source-observation deduplication receipts, stream heads, rule/control state, outbox/inbox and narrowly scoped current issue/version guards where needed for concurrent operator commands. These support EP; they do not replace historical facts. |
| Monitoring MVs | Current issue list, observation detail index, correlation timeline, delivery status, dependency health, alert status and rate/latency summaries. Rebuildable query state, never the point of truth. |

An example `MonitoringObservationRecorded` payload is:

```json
{
  "code": "tom.delivery.provider_timeout",
  "severity": "warning",
  "category": "delivery",
  "outcome": "unknown",
  "safe_message": "The delivery provider did not confirm the result.",
  "source": {"application": "tom", "component": "notifications", "release": "build-reference"},
  "source_observation_id": "source-generated-uuid",
  "observed_at": "2026-10-23T10:00:00Z",
  "received_at": "2026-10-23T10:00:01Z",
  "occurrence_count": 1,
  "fingerprint": "versioned-normalized-condition-hash",
  "related": {"business_command_id": "uuid", "delivery_attempt_id": "uuid"},
  "diagnostic": {"exception_class": "TimeoutError", "duration_ms": 10000},
  "retention_class": "operational_diagnostic"
}
```

The sample is illustrative, not an accepted API schema. A timeout remains `unknown` until reconciled; retrying must not falsely imply the original send did not occur.

### Scope, actors and stream design

- Occasion observations belong to their tenant and occasion; tenant-wide administration observations have tenant scope. Scope is derived and checked against the authenticated application binding and linked operation, not trusted from arbitrary client fields.
- Pre-login/bootstrap observations and platform failures use an explicitly restricted global scope. A failed foreign-tenant access attempt must not be written into or exposed through the target tenant merely because a supplied URL named it. Cross-tenant platform incidents have a restricted root record and separately sanitized scoped impact records where appropriate.
- Existing `event.actor_identity_id` and `command_id` are mandatory. Provision accountable, narrowly authorized service identities for TOM, EP jobs and probes; retain the initiating human as an optional restricted reference when applicable. The observation command gets its own command ID; the failed business command ID is a related reference. Never invent a human actor or reuse a failed receipt as a successful business result.
- Observation streams are bounded and partitioned by source/scope/time bucket or stable observation identity; an issue has its own lifecycle stream. Do not append every observation to the existing tenant/occasion business stream or use one global stream lock. Validate shard sizing under load rather than treating 40–80,000 concurrent users as a request-rate estimate.
- Reuse transactional append, deduplication and outbox/inbox patterns. The existing tenant-bound outbox and business projectors do not automatically support global monitoring or monitoring stream types: explicitly extend routing/storage with constraints and tests, or introduce a separate operational publication table. Never silently mark a monitoring event handled by an unrelated business projector.

### Volume and source-of-truth boundaries

Persist actionable errors, warnings, security/governance facts, delivery transitions and significant health transitions individually, subject to explicit flood controls. Aggregate repetitive expected validation failures and repetitive identical failures into bounded time windows, preserving counts and first/last occurrence references. Mark aggregated or sampled evidence clearly; never imply a complete per-request audit where sampling was used. Required security/audit evidence needs a separately sized, loss-accounted capture policy.

Do not store every CPU sample, successful HTTP request, SQL statement or stack frame as a core event. Use counters/histograms and bounded local structured diagnostics for high-frequency detail; persist meaningful aggregate windows, breaches and recoveries in `event`/`event_details`. The event facts are authoritative for the monitoring history actually recorded, not proof that every real-world failure was observed.

## Capture, correlation and safe failure handling

1. Generate/validate a bounded request reference at TOM ingress. Propagate correlation plus request/causation references through EP calls and job metadata; external integrations receive only appropriate opaque references. The existing EP correlation ID is a UUID; arbitrary inbound strings must not be copied into it unchecked.
2. Use one error catalogue with stable codes, default severity, category, safe user text, operator text template, retry/reconciliation guidance, owner and retention class. Diagnostic text never becomes raw HTML. Structured logger fields mirror the safe catalogue and correlation references.
3. Instrument Rails request/error handling, `Ep::Client`, TOM delivery, Phoenix command/error handling, database/Oban telemetry and projector boundaries. Capture compile/test/static-analysis failures as build-scoped platform observations from trusted CI when that integration exists; never pretend compile failures will be caught by runtime handlers.
4. For expected rejection, return field/action guidance and safe entered values. For an unexpected failure, show a generic action-specific message and support reference within the current view. Applications supporting Turbo Streams, Phoenix LiveView or equivalent mechanisms must use them for in-context error/status updates rather than redirecting the user to a separate error page. Preserve neither passwords/secrets nor unsafe raw input. Browser rendering alone cannot prove the person saw the result; label browser acknowledgment separately if later added.
5. Submit TOM observations through a dedicated authenticated EP API with narrowly scoped reporting credentials. Reporting an observation grants no right to query monitoring, issue roles or append business facts. Verify provider callbacks, deduplicate their IDs and validate delivery/scope binding before accepting their reported outcome.
6. Append successful business facts in their normal transaction. Capture a rejected/rolled-back operation's observation **after rollback in a separate transaction**, with an outer error boundary. Unexpected exceptions must not be swallowed or changed into success merely because recording succeeded.
7. Capture EP-internal failures through a local internal command boundary, not recursive HTTP calls into itself. Monitoring ingestion failures use bounded local structured logging and an independent health signal; do not recursively report failure of reporting. Projection replay must not re-emit alerts or send messages.

### In-context streamed user feedback

This is a cross-application requirement for all connected systems with a streaming/reactive UI capability, including TOM when Turbo support is introduced. Each application translates safe EP results and its own failures into its native view-update mechanism; EP supplies facts and status through its API, not application-specific HTML or unrestricted browser subscriptions.

- Keep the user on the current screen. Update the affected form, action-status region or inline notification using Turbo Streams/Frames, LiveView updates or an equivalent. Preserve safe entered values, selection, scroll and keyboard focus; announce changes through an accessible live region. Never broadcast submitted form values or personal error details to other users.
- For a TOM code bug producing a 500, the outer error handler should return a minimal independently renderable update containing a safe action-specific explanation and support reference. Retain the failure classification in HTTP status where applicable and monitoring even when presenting it inline. Test the framework's handling of non-success responses; add the necessary client error handling rather than assuming a 500 response will automatically apply a stream update. Do not reuse a failing view/component in the fallback renderer.
- If EP accepted the action before TOM failed, show “Checking whether your request completed” while bounded reconciliation queries the original command/idempotency reference. Then update the same region to confirmed success, confirmed rejection or an explicit unknown result with safe next steps. Do not label an accepted operation failed or automatically repeat it. If no reconciliation endpoint exists yet, implement that API capability before promising automatic resolution.
- Continue streaming relevant pending/projection/delivery status into the existing view when available. Distinguish accepted, updating, provider accepted, delivered and unknown; remove a loading indicator on failure or timeout without manufacturing a final outcome. Each update carries an operation/version reference so duplicate or late updates cannot overwrite newer state or another form's result.
- Authorize subscriptions and every delivered update against current scope and grants; terminate or suppress delivery after revocation, sign-out or expiry. Scope channels to the appropriate tenant/occasion and, for request-specific feedback, session/identity/operation. Send only safe representations, never raw monitoring payloads. Reconnection fetches current authorized state rather than blindly replaying old private messages or resubmitting the action.
- If the process crashes, the connection drops, a proxy supplies the 500, or rendering itself fails, an application stream may be impossible. A small client-side boundary should retain the current view and show a connection/request failure when it is still running. Provide a minimal same-view HTML response or safe error page only as a fallback for full navigation, unavailable streaming/JavaScript or an unrecoverable page. The monitoring capture path must work independently of whether a view update reaches the browser.

Streaming is presentation and transport, not persistence or proof of user acknowledgment. It neither undoes accepted EP facts nor replaces command idempotency, outcome reconciliation and event-based monitoring.

### When EP or its database is unavailable

The failed dependency cannot be the only way to record its own outage. EP/TOM emit sanitized structured logs independently of EP persistence; external probes check liveness, readiness and missing heartbeat/ingestion signals. A managed collector can spool a bounded, encrypted, expiring backlog and retry stable source-observation IDs after recovery. This is operational transport, not a TOM business database; spool-full and dropped-count signals must be explicit.

Until such a collector exists, make the limitation visible: local logs and independent probes are the fallback, and loss of process-local observations is possible. TOM must not retain an unbounded in-memory queue or block user responses indefinitely on monitoring submission. Define a short reporting timeout and bounded concurrency; replay the backlog at a rate that does not delay EP recovery. Preserve source occurrence time separately from EP receipt time.

## Near-real-time projections and alerting

Publish committed monitoring facts to dedicated monitoring queues with reserved capacity and bounded retries. Incrementally update MVs and inbox/checkpoints atomically. Use safe committed publication and per-stream order, not a numeric event-ID high-water scan. Query indexes should start with authorized scope and support severity/state/time, stable code, application and correlation lookup.

Separate occurrence deduplication `(authenticated source, source_observation_id)` from issue grouping by versioned fingerprint. Fingerprints exclude secrets, person names and free text and include scope so unrelated tenants never merge. New occurrences can increment an issue's count; severity escalation and recurrence after resolution produce explicit lifecycle facts. Grouping never discards the underlying retained observations.

Alert on sustained conditions with a recovery threshold, cooldown and maintenance window. Proposed initial configurable targets, to validate in testing:

| Signal | Initial target/trigger | Response |
|---|---|---|
| Accepted monitoring fact visible in TOM | p95 within 5 seconds under agreed load | Show checkpoint/last update; warn if lag persists above 30 seconds. |
| Critical condition notification | Request within 60 seconds of detection | Notify the duty operator through the responsible delivery application. Track provider acceptance separately. |
| EP/TOM readiness | Three consecutive failed 15-second probes | Independent outage alert; recovery after three successful probes. |
| Unexpected request errors | Above 1% and at least 10 failures in 5 minutes | Group by safe code/release/scope; exclude expected rejections. |
| Projection backlog | Oldest pending committed item above 30 seconds for 2 minutes | Warn; escalate at 5 minutes, and immediately on exhausted projection jobs. |
| Delivery failure | Permanent rejection or exhausted safe retry | Immediate issue; unknown sends require reconciliation before retry. |
| Missing monitoring ingestion | No expected heartbeat for 60 seconds | Independent signal; distinguish source stopped, pipeline delayed and EP unavailable. |

Latency buckets, database-pool limits and capacity alerts must follow measured baselines. Tenant admins configure only approved rules within their scope; platform minimum security/availability coverage cannot be disabled by a tenant. Suppressions require reason, owner and expiry and suppress notification, not evidence capture.

Alert delivery is an explicit side effect with a stable operation key and separate executor. EP records intent/outcomes; TOM or the designated notification application owns provider integration. Replay rebuilds views without re-sending historical alerts. Delivery failures are grouped and routed to an independent fallback rather than recursively generating unlimited delivery alerts.

## TOM monitoring list and drill-down

Add **Monitoring** to navigation only where current EP authority allows it. Default tenant admins see their tenant's operational summary; occasion admins see operational records for their occasions. Restricted security, identity, raw diagnostics and platform records require additional explicit permissions even for administrators. Global monitoring is a separate platform-operator surface, never implicitly included in tenant administration.

The principal screen is a list, not a chart dashboard. Default to unresolved warnings/errors/critical issues, most severe first, then latest occurrence; provide a separate chronological observation list including informational outcomes. Always show selected scope, active filters, freshness and whether data is partial or stopped.

```text
Monitoring / Spejdernes Lejr / SL2030
Last updated 10:00:05 · projection lag 2s
[Open 8] [Critical 1] [Warnings 5] [Delivery 2] [All observations]

Scope [SL2030]  Application [All]  Severity [Warning+]  State [Open]
Category [All]  From/to [...]  Code/reference [...]  [Apply] [Clear]

Severity  Last seen  Application  Issue                         Count  State       Owner
Critical  10:00:03   EP           Projection processing stopped    14  Open        Unassigned
Warning   09:59:42   TOM          Delivery confirmation missing      2  Investigate Platform duty

[Previous]  Showing 1–50  [Next]
```

Each row opens a detail page or accessible expandable panel containing:

1. Safe summary, code/severity/category, first/last occurrence, count, scope, current state and owner.
2. User impact and suggested next action; distinguish acceptance, response failure, projection delay and uncertain delivery.
3. Chronological correlated timeline: browser/TOM request, EP decision and event IDs, projection/job progress, delivery attempt/provider outcome, operator actions and recovery. Links appear only if the viewer can access the referenced record; cross-scope correlation never expands authority.
4. Authorized observation details: release/component, sanitized trace, source/receipt times, attempt/checkpoint and correlation/support references. Default users see safe explanations; technical diagnostics are separately gated.
5. Explicit actions: acknowledge, assign, add a bounded sanitized operational note, resolve with reason, reopen, or create/link a WorkItem when that capability exists. Notes are retained content subject to the same privacy controls, not a place for personal narratives.
6. Contextual recovery links to separately authorized workflows. No generic “retry” button that replays business commands, re-sends ambiguous messages, restarts stopped MVs or grants extra permissions.

Use server-rendered Phlex/Tailwind views, accessible severity text alongside color, keyboard-operable controls, wrapped summaries and a stacked row layout on mobile. Filters use validated allowlists and bounded time ranges; no raw payload search or arbitrary SQL. Use stable cursor pagination, default 50/max 100 rows, with a fixed query cutoff for paging during incoming updates. Where streaming is supported, update issue details, action results and freshness in place; announce new matching issues with an “N new issues” control instead of unexpectedly reordering the list. Preserve filters, cursor position, expanded rows and focus. Manual refresh and bounded polling are fallbacks when a stream is unavailable.

A stopped monitoring MV returns unavailable/stopped, never a stale successful-looking list. Newly acknowledged items can show EP's accepted version plus “updating list” until the MV catches up. Empty results, forbidden access and unavailable monitoring are distinct safe states. Exports are permission-gated, scope-filtered, bounded, audited and expiring; no bulk raw-detail export by default.

## API surface

| Operation | Contract |
|---|---|
| `POST /api/v1/monitoring/observations` | Authenticated source, validated schema, derived scope and source ID/idempotency. Returns accepted event IDs or explicit rejection; a duplicate returns the same accepted result. Bounded batches can follow after a measured need. |
| `POST /api/v1/monitoring/delivery-outcomes` | Optional reporting capability for an authorized delivery backend; evidence provenance and attempt binding required. Reports never redeem a challenge or confer an invitation grant. |
| `GET /api/v1/tenants/:tenant_id/monitoring/issues` | Filtered MV list; optional allowed occasion filter, stable cursor, freshness/checkpoint and authorized counts. |
| `GET /api/v1/tenants/:tenant_id/monitoring/observations` | Bounded chronological observations, including authorized code/reference lookup. |
| `GET /api/v1/tenants/:tenant_id/monitoring/issues/:id` | Current issue summary and authorized paginated timeline; sensitive fields explicitly omitted. |
| `POST /api/v1/tenants/:tenant_id/monitoring/issues/:id/actions` | Allowlisted action, current authority, expected lifecycle version and idempotency key; emits lifecycle facts. |

The initial routes are implemented in [Monitoring API v1](../systems/ep/docs/monitoring-api.md); that document and its OpenAPI contract define the supported payloads, pagination and current limitations. Platform/global access now has separate endpoints and explicit operator grants; see the local implementation status below. All reads enforce current identity, scope, purpose, token and MV controls before serving data, including counts, references and exports. TOM uses only EP's API; no direct PostgreSQL queries, shared mailbox or independent monitoring store.

## Privacy, retention and operational ownership

Exclude raw form bodies, email/phone/postal details, message bodies, images/audio, bearer tokens, magic-link values, session cookies, backend credentials, connection URLs and full query strings. Use route templates rather than captured URLs. Error messages and stack locals can contain secrets: allowlist fields before logging or ingestion and test with planted secrets. Opaque identity IDs and fingerprints can still be personal data; protect related metadata and links as well as payload text.

Apply the privacy/erasure model in [gdpr.md](gdpr.md) to monitoring source facts, MVs, log collectors, trace artifacts, exports and backups. Proposed defaults are 30 days for detailed operational diagnostics and 90 days for issue lifecycle/aggregate history, with separate approved security/legal schedules. These are planning defaults requiring owner review, not a claim of legally sufficient retention. Open issues do not indefinitely retain every personal detail. Retention exceptions need purpose, authority, expiry and restricted access.

Maintain a subject/reference index for retained identifying evidence; suppress serving promptly on an approved erasure action, then redact/delete eligible metadata, details and derivatives within the governing deadline. Rebuild must apply suppression and retention boundaries. A redaction marker records the action without retaining the erased identifier. Logs/spools and backup copies must be included in the established custodian/restore sanitation process.

Digital Platform owns capture contracts, EP persistence, monitoring queues/MVs and platform on-call. Application owners own error codes, user messages and delivery reconciliation. Tenant/occasion administrators own authorized operational follow-up; restricted security cases go to designated security/privacy responders. Each alert rule needs a named responder and a short runbook, not only a recipient address.

## Implementation priorities and acceptance

| Order | Deliverable | Required evidence before completion |
|---|---|---|
| 1 | Error catalogue, safe structured logs, request/correlation propagation, service identities and redaction policy | Trace one operation TOM → EP → projection/delivery without exposing planted secrets. Expected input failures remain actionable and distinct from exceptions. |
| 2 | Monitoring commands, event/details schemas, scope checks, deduplication and dedicated publication path | Repeat submissions persist once; rejected business work creates no success fact; rollback capture works; foreign scope is rejected; global capture does not violate current envelope/outbox constraints. |
| 3 | Failure-safe collection, independent probes and monitoring MVs | Kill EP/database and demonstrate independent outage visibility, bounded backlog/loss accounting and recovery without flooding; inject duplicate/out-of-order publication and verify convergence. |
| 4 | TOM issue/observation list, filters, drill-down, lifecycle actions and in-context streamed feedback | Browser-check desktop/mobile, accessibility, stale/stopped states, pagination, revoked access and tenant/occasion/security isolation. Inject a TOM exception before and after EP acceptance: the current view and safe input remain, the support reference appears, reconciliation does not duplicate the action, and late/duplicate updates cannot overwrite newer state. Test 500 stream handling, disconnection, process crash, reconnection and non-stream fallback. Concurrent actions use expected versions. |
| 5 | Delivery outcomes, rules, alerts, assignment/runbooks and integration hooks | Distinguish provider acceptance/delivery/bounce/unknown; verify callbacks; prevent duplicate side effects and alert loops; replay sends nothing. |
| 6 | Retention/erasure, capacity, recovery and operational rehearsal | Demonstrate deletion across source/derived/log/artifact paths and safe restore/rebuild; measure ingestion/lag/query impact under representative concurrency and failure storms. |

Priorities 1–4 establish the first usable monitoring slice; independent outage detection is required before calling it operational. Build/release integration, richer external-provider evidence and specialized analytics can extend it without replacing the core event contract. No monitoring implementation should be described as production-ready until its isolation, failure, privacy, capacity and responder ownership checks pass.

## Local implementation status — 2026-10-26

Implemented the remaining local operational slice: independent loopback probes/collector, encrypted bounded queues shared by EP/TOM, automatic opt-in EP telemetry aggregation, scoped source registration/revocation, configurable threshold/window/cooldown alerts and suppression, TOM alert worker, current-admin assignment, explicitly granted platform/diagnostic access, monitoring retention/erasure suppression, snapshot-consistent encrypted backup inventory and unpublished local restore sanitation.

The [runbook](../systems/monitor/README.md) documents processes, credentials and safety boundaries; [local rehearsal evidence](../systems/monitor/local_rehearsal.md) records actual results. Supporting control/work/subject tables do not replace `event`/`event_details` as fact storage. Rebuilds and durable acknowledgment retries never send external messages.

This completes the locally implemented controls, not all production acceptance criteria above. In particular, local `.notices` provides independent outage visibility but has no production paging adapter; retention holds, all-domain/third-party erasure, immutable/offline original retirement, provider delivery callbacks, real-browser/accessibility checks and representative peak-load/failure-storm evidence remain open. [pending_details.md](pending_details.md) is the deployment decision/evidence register. Do not describe backup erasure as complete merely because monitoring content was sanitized.
