# System 5 Plan — Ticketing and Service Management

## Purpose and status

Deliver **system 5 in [suggested_systems.md](suggested_systems.md)**: participant support, operational requests, work orders, assignment, escalation, service levels and resolution tracking. This numbering follows the system catalogue; it is distinct from the implementation-plan numbering used in [system_2_plan.md](system_2_plan.md).

This is an initial implementation plan, not a statement that ticketing is implemented. It follows [domain.md](domain.md), [entity-relationship.md](entity-relationship.md), [organization.md](organization.md), [prioritized_functions_systems.md](prioritized_functions_systems.md), [system_1_plan.md](system_1_plan.md), [architecture.md](architecture.md), [suggested-data-store.md](suggested-data-store.md), [gdpr.md](gdpr.md) and [monitoring_plan.md](monitoring_plan.md).

Participant Experience and Programme owns common intake and the service-management process. Each portfolio owns resolution within its functions. Safety, Safeguarding and Emergency Readiness owns incident classification, restricted handling and escalation into system 6. Digital Platform owns the shared technical contracts and operation.

The first delivery is the P0 WorkItem planning spine: accountable owners, dependencies, review queues and lifecycle tasks. Participant service follows in P1, operational integrations in P2, and full duty coverage and rehearsals in P3. GIS, scheduling and the complete emergency-command product are not prerequisites for the first planning task.

## Outcomes and boundaries

| Capability | Planned result | First delivery |
|---|---|---|
| Planning and lifecycle work | Tasks with owners, dependencies, due dates and traceable completion | P0 |
| Intake and triage | Support desk and participant reports, categorization, impact, urgency and routing | P1 |
| Service execution | Accepted assignments, work orders, handovers and resolution evidence | P1; field integrations in P2 |
| Service levels | Versioned calendars, response/resolution targets, breach detection and escalation | Basic due dates in P0; service policies in P1 |
| Operational overview | Scoped queues, workload, overdue work and location-linked issues | Queue MVs in P0; geographic view in P2 |
| Restricted review | Minimal workflow references to safeguarding, privacy and safety cases | P0 where needed; specialist details remain separately controlled |
| Incident handoff | Tracked referral and confirmed ownership transfer to system 6 | Contract in P1; rehearsed operational integration in P2 |

System 5 coordinates work. It does not own registration or safeguarding decisions (2), workforce eligibility and shifts (3), emergency command (6), GIS geometry (7), message transport and alarms (8), stock (11), financial posting (12/13), facility master records (15), resource reservations (18), or controlled procedures (19). It links to these authoritative records and records the outcomes relevant to work progress.

Activity workflows may reuse the WorkItem spine later. Participant capacity, booking and staffing remain governed by systems 2/3/18 and are excluded from the initial ticketing slice.

## Shared work model

Use the common model in [entity-relationship.md](entity-relationship.md). `WorkItem` is the shared operational identity; `Task`, `ServiceRequest` and `Incident` carry their respective semantics. A ticket is an intake and presentation view over that work, retaining its conversation and history. Do not create a parallel Ticket tree with independent ownership and status.

| Record | Required meaning |
|---|---|
| WorkItem | Stable opaque ID, tenant/occasion scope, kind, safe summary, classification, lifecycle, revision and accountable owner |
| Task | Planned or assigned work, completion criteria, optional parent and dependency links |
| ServiceRequest | Reported need, intake source, reporter/contact reference, category and desired service |
| Incident link | Reference to an incident and its authoritative owner, handoff state and permitted summary |
| Assignment | Responsible team/person, responsibility type, offer/acceptance state, validity and handover history |
| Conversation entry | Author, audience, timestamp, revision/correction history and controlled content reference |
| Service policy | Versioned routing, impact/urgency rules, service calendar, targets and escalation rules |
| Relationship | Typed parent, dependency, duplicate, related problem, location, asset, procedure or source reference |

Occasion work carries both `tenant_id` and `occasion_id`. Genuine tenant-level planning may omit occasion scope explicitly; never infer access to all occasions from that omission. Every linked identity, membership, team, work item and resource must resolve within permitted scope. Cross-occasion or cross-tenant references require an explicit sharing contract and are excluded from the first slice.

Each active item has one accountable owner, initially the intake team when no resolver has accepted it. Contributors and subtasks do not dilute that accountability. A team owner must have a named duty contact or an explicit coverage gap. Reporter, affected person, requester and assignee are distinct roles; creating a report grants no resolver privileges.

Keep semantic `Location` references stable when map geometry changes. Store unverified free-text locations as such until reconciled; work can start without a map coordinate. A location or asset link never grants access to its underlying restricted data.

## Lifecycle, triage and resolution

Proposed initial lifecycle:

`new → triaged → queued → in_progress → resolved → closed`

`waiting`, `cancelled` and reopening are explicit governed transitions. Planning tasks may enter `queued` directly after validation. Keep assignment, incident handoff, confidentiality and SLA state separate from lifecycle status.

- Intake creates one accepted item and receipt. Record channel and source provenance for participant forms, support desks, telephone/radio operators, manual field reports and integrations. Operators acting on behalf of someone retain their own attribution.
- Triage establishes category, impact, urgency, proposed priority, visibility and routing. Severity describes consequences; priority determines service order under an adopted policy. Agents may suggest classifications, but cannot silently declare an emergency resolved or lower a safety classification.
- Assignment offers and acceptance are recorded separately. Until a receiving owner accepts a handover, the existing owner remains accountable. Atomic conditional claims prevent two responders from independently claiming exclusive responsibility.
- Waiting requires a reason, responsible follow-up party and review time. Dependency waits do not automatically pause targets. Escalation preserves an owner until a replacement accepts.
- Resolution records outcome code, safe explanation, work/evidence references and unresolved follow-up. Closure follows requester confirmation or an adopted closure policy. Reopening records a reason and starts a new service cycle without erasing the previous result or breach history.
- Cancellation and duplicate designation require authority and a reason. Link duplicates to the surviving item while preserving report provenance and audience restrictions. Do not copy restricted comments into a broader parent or notify all reporters of each other's identities.
- Parent/child and blocking dependencies must be tenant/occasion-valid and acyclic. Protect concurrent graph edits. Reject completion where mandatory child work or dependencies remain incomplete unless an authorized exception is explicitly recorded.

Freeze the transition matrix, required fields and exception permissions before implementing handlers. Reassignment, merge/link operations and classification changes use expected versions; stale editors receive conflicts and refresh rather than overwriting newer work.

## Safety boundary and incident handoff

Participant intake and operator screens must make the adopted emergency route visible. A submitted report, queued message or suggested responder is not confirmed dispatch. Suspected immediate danger follows the current emergency procedure even if EP is unavailable.

Record incident referral with correlation ID, proposed classification and only the permitted context. System 6 returns accepted incident identity, accountable command owner and acknowledgment. Show pending, accepted, rejected or failed handoff explicitly; retain local follow-up ownership while pending. Track dispatch acceptance, responder acknowledgment and arrival as distinct facts when provided by the responsible system.

Safety defines who may classify, restrict, downgrade and close safety-related work. Routine service users receive a minimal operational summary and a restricted-case reference, not medical, child-protection or security narratives. Revoking visibility must affect current queries, search, attachments, queued disclosures and existing exports under their lifecycle contract. Do not wait for a projection to catch up before enforcing restriction.

System 5 may track routine service incidents without assuming command authority. Linking many outages or observations to a major incident preserves the original requests, ownership and restricted audience boundaries.

## Service levels and escalation

Service owners must adopt actual targets; this plan does not invent response-time promises. A policy version defines category/priority eligibility, service timezone/calendar, coverage hours, first human response, assignment acknowledgment, resolution target, permitted pauses and escalation recipients.

Store server acceptance time, source-reported occurrence time, target basis and calculated deadlines separately. An automated receipt does not count as a human response. Persist pause intervals and policy changes with reasons. Reprioritization uses an explicit recalculation rule; it cannot erase an already recorded breach. Display original and revised targets where relevant.

Durable deadline jobs use a stable key for item, service cycle, target type and policy revision. On execution, recheck current item state, deadline and authority before recording a breach or escalation intent. Recovery scans detect missed deadlines after downtime. Duplicate/retried jobs cannot create repeated escalation facts or repeated external actions. Escalation recipients need time-valid duty coverage, alternates and a visible fallback when nobody acknowledges.

P0 uses ordinary due dates and overdue views. Full service calendars and pause accounting follow after the basic ownership lifecycle is proven.

## Authorization and privacy

System 1 supplies current identity, application binding, grants and delegation. System 5 evaluates action, tenant, occasion, owner/team, audience, classification and case purpose. Platform or tenant administration alone does not confer unrestricted case access.

Proposed permissions include `service.request.create`, `service.request.read_own`, `service.triage`, `service.assign`, `service.assignment.accept`, `service.work.update`, `service.resolve`, `service.close`, `service.reopen`, `service.policy.manage`, `service.case.restrict` and `service.report.read`. Restricted case access and exceptional closure/downgrade require separate explicit authority. Freeze permission names and role mappings with owners before live use.

Participant views expose only permitted request details and public replies. Resolver-only notes, restricted notes and participant replies have explicit audiences; changing a note's audience requires validation. Validate requester/guardian/representative relationships through their authoritative systems. Knowing a ticket number or contact email is not authentication or access authority.

Keep personal narratives, precise sensitive locations and attachments in controlled payload/artifact storage. Event envelopes, URLs, metrics, notification previews and generic logs contain minimal opaque references. Scan uploads, constrain size/type, quarantine unsafe content, authorize every download and avoid publicly reusable attachment URLs. Search indexes and notification payloads obey the same restrictions as detail views.

Adopt purpose-based retention for request bodies, conversations, attachments, assignment history, exports and device caches before personal-data intake. Apply subject indexing, rights workflows, holds, erasure propagation, backup handling and replay suppression from [gdpr.md](gdpr.md). A restricted rights-case task may expose owner and deadline to the appropriate queue without exposing the underlying request. An appended deletion event alone does not erase earlier payloads.

## Application and EP architecture

Extend EP with work-domain handlers and scoped query endpoints. Use a separate service-management application/backend integrating through EP APIs. Proposed UI stack is the existing Rails/Tailwind/Phlex/Turbo pattern used by TOM and VERA; confirm the application name and deployment boundary in the first implementation slice. Ordinary accepted business state remains authoritative in EP rather than an independently writable application database.

Browsers call the application backend. Backend authentication preserves the actual operator, represented identity and valid delegation; machine integrations have bounded scopes and explicit source identities. No shared database or filesystem mailbox forms the application contract.

Accepted commands atomically append `event`/`event_details`, advance stream versions, update required consistency state, record idempotent receipts and enqueue durable publication. Protected state enforces ownership, transitions, graph constraints, policy versions and current authorization. Routine queues, histories and dashboards use background-maintained MVs.

Suggested accepted events include `WorkItemCreated`, `WorkItemTriaged`, `WorkItemOwnerChanged`, `AssignmentOffered`, `AssignmentAccepted`, `WorkStarted`, `WorkWaiting`, `WorkResumed`, `WorkResolved`, `WorkClosed`, `WorkReopened`, `WorkCancelled`, `DependencyAdded`, `DuplicateLinked`, `ConversationEntryAdded`, `CaseRestricted`, `ServiceTargetSet`, `ServiceTargetBreached` and `IncidentReferralRecorded`. Final schemas must distinguish offers from accepted transfers and personal payload references from safe operational fields.

Proposed API groups under `/api/v1/tenants/:tenant_id/occasions/:occasion_id`:

| API group | Contract |
|---|---|
| `work-items` create/list/detail | Scoped creation and cursor-based authorized queries; explicit kind and source |
| Work-item transition commands | Expected revision, idempotency key, reason and transition-specific fields |
| Assignments and ownership | Offer, accept, decline and handover with protected owner invariants |
| Conversations and attachments | Explicit audience, controlled upload/download and safe metadata |
| Relationships and incident referrals | Validated references, graph guards and correlated handoff outcomes |
| Service policies and queues | Versioned configuration, owner authority and effective dates |

Tenant-only planning uses a separately explicit scoped route. Do not make missing occasion scope a wildcard. Return stable accepted IDs/versions, validation errors, authorization denial, version conflict or pending integration outcome. Same-key/same-payload retries return the original accepted result; key reuse with a changed payload is rejected. API names here are proposed, not existing endpoints.

## Projections, communications and integrations

Initial MVs cover my work, team queues, unowned/unacknowledged work, due/overdue work, dependencies and authorized item history. Add service-level performance, location summaries, incident-linked work and readiness dashboards incrementally. Every query exposes freshness/checkpoint state and enforces current access independently of MV content. Support bounded read-your-write waits or show the accepted command result while projection catches up.

Integrations publish permitted representations with source IDs, schema versions, correlation and stable deduplication keys. Separate a new report from a repeated observation of an existing problem; integrations must define correlation and recovery rules rather than suppressing every future recurrence under one permanent key.

| Integration | Ownership and boundary |
|---|---|
| Identity (1) | Canonical actors, scoped teams, current grants and delegation |
| Registration/workforce (2/3) | Restricted eligibility/contact references and qualified responder availability; no wholesale profile copies |
| Incident command (6) | Referral acceptance, command ownership and permitted response outcomes |
| GIS (7) | Semantic locations, geometry versions and authorized operational layers |
| Communications (8) | Audience/channel delivery and acknowledgment; delivery success is distinct from assignment acceptance |
| Monitoring/facilities (9/15) | Observations and failures create/update corrective work with source provenance |
| Inventory/finance (11/13) | Material requests and approved cost references; resolving work does not itself issue stock or post money |
| Scheduling/documents (18/19) | Governed reservations and versioned procedures/completion checklists |
| Reporting/platform (20/21) | Scoped feeds, projection health, lifecycle propagation and reconciliation |

Application/integration backends own provider execution and credentials through explicit API handoffs. Durable operational notification intents need operation IDs, retry ownership, outcomes and current disclosure checks. Reuse a suitable system 8 contract as available; do not change the existing EP authentication/invitation response-delivery contract. Never equate notification creation with delivery or responder acknowledgment. Replaying a projection cannot resend messages, redispatch teams or create fresh external work orders.

## Offline operation and reliability

Start with online coordination and an adopted radio/telephone/manual fallback. Later field capture may use encrypted, bounded device storage with explicit expiry, local capture IDs and source timestamps. Mark unsynchronized reports clearly; they have no server acceptance, confirmed dispatch or guaranteed SLA coverage until reconciled. Restrict sensitive caching and define device revocation, deletion and lost-device handling before enabling it.

On synchronization, deduplicate source IDs, retain original occurrence times, revalidate current authority and resolve version conflicts visibly. Never overwrite current ownership or incident state using an older offline copy. Minimize cached requester data and remove it after acknowledged synchronization under the device policy.

Monitor command failures, projection lag, queue age, orphaned ownership, unacknowledged assignments, deadline-worker delay, pending incident referrals and unresolved delivery outcomes. Use [monitoring_plan.md](monitoring_plan.md) for technical observations; a technical monitoring issue and a human service WorkItem remain distinct linked concepts. Reconcile timers and integration results after recovery. Rebuild MVs into verified generations with current privacy suppression before switching readers.

## Delivery sequence and acceptance

| Slice | Deliverable | Acceptance evidence |
|---|---|---|
| 0 — Contract and ownership | Transition matrix, work schemas, scope rules, permission mapping, accountable owners and restricted-case boundaries | Owners approve representative planning, participant, utility-failure and safety-referral examples; unresolved policy decisions have named owners |
| 1 — P0 planning spine | Create/read/update Task, accountable team, due date, dependencies, resolution/reopen, scoped queue/history MVs and minimal UI | Two tenants and sibling occasions prove isolation; retries create one item; concurrent claims preserve one owner; graph cycles and stale writes fail |
| 2 — P0 lifecycle review | Restricted task queues and idempotent source-generated review/expiry work | Retry creates one task per source cycle; ordinary admins cannot read restricted payloads; completion requires the owning domain's accepted outcome |
| 3 — P1 participant service | Desk and authenticated requester intake, triage, conversations, assignments, work orders and requester view | End-to-end report → triage → accepted assignment → response → resolution → closure/reopen, including audience and attachment restrictions |
| 4 — P1 service policies | Versioned calendars, response/resolution targets, waiting rules, escalations and duty handovers | Calendar boundaries, pause/repriority rules, downtime catch-up and duplicate jobs preserve deadlines and breach history |
| 5 — P2 operational integration | Location/map view, facility/monitoring feeds, qualified scheduling links, incident handoff and notification outcomes | Duplicate observations, failed handoff, absent responder, communications outage and restricted incident scenarios are rehearsed |
| 6 — P3 readiness | Load/recovery validation, duty coverage, procedures, retention/restore checks and operational rehearsal | Agreed service envelope is met, restoration cannot redispatch or resurrect erased data, and owners sign off unresolved operational risks |

The first implementation should be a narrow Task vertical slice in EP and the application UI. It must prove accepted-event authority, owner enforcement and derived queues before adding participant narratives, elaborate SLA calendars or map dispatch. Existing EP foundations are reusable; full permission administration, generic fan-out and privacy-aware replay must be verified or extended where this slice depends on them.

Verification should cover meaningful failure modes: concurrent transfer/closure/restriction, replay after erasure, audience leakage through search and notification previews, stale projections after revocation, timer retries after downtime, external success followed by a lost acknowledgment, and offline synchronization conflicts. Load scenarios must include burst intake and a widespread utility outage with many related reports; owners must agree rates, concurrent operators, payload limits, projection lag, recovery targets and retention volumes before production acceptance. Participant population alone does not establish a capacity claim.

## Decisions to resolve before their delivery gates

| Decision | Accountable owner | Gate |
|---|---|---|
| Initial categories, transition exceptions, resolution codes and routing teams | Participant Experience with portfolio service owners | First domain contract |
| Tenant-level planning scope and first application name/deployment | Digital Platform with service owner | First implementation |
| Queue owners, duty contacts, alternates and handover acceptance rules | Each portfolio | Live assignment |
| Authenticated versus anonymous participant reporting, representation and abuse controls | Participant Experience with Safety and privacy lead | Participant intake |
| Severity policy, emergency route, restricted audiences and incident referral acknowledgment | Safety | Safety-related intake and hazardous build |
| Service hours, calendars, target values, pause rules and escalation fallback | Service owners | Publishing service commitments |
| Retention, attachment controls, personal-data fields, rights and offline policy | Accountable processing owner with privacy lead | Personal-data activation |
| Work-order authority, material/cost approvals and external source ownership | Facilities, Logistics and Finance as applicable | Relevant integration |
| Operating envelope, recovery targets and rehearsal acceptance | Digital Platform with service owners and Safety | Operational acceptance |

These decisions refine the plan; they do not block drafting or development of the isolated P0 planning spine using non-sensitive fixtures.
