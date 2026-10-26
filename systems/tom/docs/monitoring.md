# Monitoring and in-context feedback

TOM uses [EP Monitoring API v1](../../ep/docs/monitoring-api.md) for monitoring persistence, lists, issue timelines/actions and accepted-command reconciliation. It has no monitoring database, cache, durable reporting queue, Action Cable channel or direct EP SQL access. Turbo is served locally through Propshaft; no JavaScript bundler or Node runtime is needed to run TOM.

## Enable persisted TOM reporting

First ensure EP's monitoring migration is applied and both applications use the same backend credential. Register reporting sources with EP's **operator CLI**, outside TOM's runtime:

```sh
cd systems/ep
export DATABASE_URL="ecto://$(whoami)@localhost:5432/sl2030_ep_dev"
mix ep.monitoring.source tom global
mix ep.monitoring.source tom TENANT_UUID
mix ep.monitoring.source tom TENANT_UUID OCCASION_UUID
```

Each command prints a non-secret source UUID. Export the mapping in TOM's shell/deployment configuration, replacing placeholders with those IDs, then restart TOM:

```sh
export TOM_MONITORING_SOURCES_JSON='{"global":"GLOBAL_SOURCE_UUID","tenant:TENANT_UUID":"TENANT_SOURCE_UUID","tenant:TENANT_UUID:occasion:OCCASION_UUID":"OCCASION_SOURCE_UUID"}'
```

Use canonical lowercase UUIDs. The backend ID `tom` must match EP's credential binding; provision separate scopes for every tenant/occasion TOM may report for. A global source covers pre-login failures and failures without established scope; it does not make global records visible to tenant administrators. EP currently has no platform-global monitoring query UI. Do not use a tenant source as the global fallback.

Without a matching source (or with invalid configuration), TOM still logs sanitized evidence and can read existing authorized EP monitoring records, but new observations are not persisted to EP. The scope selector explains when reporting is unconfigured. Retrying, spooling and eventual recovery of failed reporting are not implemented: ingestion timeout/failure produces a separate local `monitoring.capture_unavailable` marker, and unconfigured persistence emits `monitoring.persistence_unconfigured`. An independent collector/probe remains necessary for process/node failures or sustained EP outages.

## Capture and correlation

Each controller request gets a UUID correlation reference returned in `X-Correlation-ID` and propagated to EP. Browser operation UUIDs in `X-TOM-Operation-ID` only correlate presentation updates; they confer no authority. Request-local state is reset for each controller dispatch. EP mutations retain the original command type/key in request memory for reconciliation and add a business-command reference to reporting when the accepted command ID is known. Bodies, raw delivery material and safe form values are not copied into monitoring state.

TOM captures unexpected controller/view exceptions, EP timeouts/errors, ordinary validation/conflict/access outcomes and delivery attempts. Severity/outcome/message are EP catalogue-owned. Expected rejections are not labeled code defects. Reporting derives its tenant/occasion key only from a successful authorized EP business call in the same request, never directly from a route parameter. A failed foreign URL lookup therefore reports globally, if configured. Monitoring and completion-check errors log locally rather than recursively reporting through the failing monitoring facility.

Local JSON evidence includes stable code, correlation and, for exceptions, class plus bounded file-basename/line/method frames. No raw exception message, arguments, form body, message content, credential or full path is included. Rails filters all form/query parameter values. Its native rescued-exception log callback is overridden to emit class/correlation only, because Rails 8.1 otherwise logs the raw exception message before TOM handles it. EP receives only its allowlisted observation fields; technical frames stay in local operational logs pending a restricted diagnostics contract.

Reporting is best effort, synchronous and bounded: 0.5-second connect/read/write timeouts, no automatic HTTP retries. This is not a durable transport or a guaranteed end-to-end 0.5-second deadline. Do not interpret successful user feedback as proof that reporting reached EP.

## User experience

For Turbo form submissions, validation errors, unexpected code failures, expired sessions and EP failures update the existing `tom-feedback` region using a Turbo Stream while retaining HTTP failure status. The original form and ordinary entered values remain in the DOM; loading ends, feedback is announced accessibly, and a support reference is shown. Token/code/password fields are cleared after feedback. The stream contains a minimal Phlex fragment independent of the failed page view. HTTP/non-JavaScript and unrecoverable navigation retain safe HTML error fallbacks.

If a receipted mutation may have succeeded, feedback links to a signed completion-check token bound to a random nonce in the encrypted session and valid for ten minutes. No Bearer/backend credential or submitted personal data enters that token. The endpoint reuses the original user's EP session and queries the exact original command type/idempotency key. It does not invoke the mutation again. The browser performs at most three same-origin, no-store GET checks with a four-second request timeout; manual checking remains available while its token is valid.

`accepted` means EP recorded the command, not that a message was delivered or that its MV is current. `unknown` remains explicitly unknown, including an in-flight command; the user is told not to start another submission. Participant-only receipt access remains constrained by EP's current admin-context policy; an inaccessible check cannot establish failure. Auth challenge issuance has no receipt, so it cannot use this completion lookup.

The originating form is guarded against repeat submissions when completion is unknown or accepted, until refreshed. Operation IDs prevent delayed feedback from overwriting a newer operation; navigation cancels outstanding completion checks. Non-stream proxy/server failures and connection loss are intercepted on the client to preserve the current view and show an uncertainty message. If the page/client itself is unavailable, an in-context update cannot be guaranteed.

Turbo uses same-origin external scripts, no page snapshot caching or link prefetching, and an accessible feedback region. CSP keeps third-party/inline scripts prohibited; a per-response style nonce authorizes Turbo's progress stylesheet without `unsafe-inline`. Native form posts and all operator actions retain Rails CSRF protection and EP authority checks.

## Monitoring screens

- **Monitoring** in navigation (`/monitoring`) lists current authorized tenants and occasions from EP workspaces. The tenant and occasion overviews link directly to their scope.
- `/tenants/:tenant_id/monitoring` lists issues (default state `open`) or observations, with severity/state/application/code/correlation filters, cursor pagination and scoped freshness/pending counts. EP v1 provides exact severity filters and insertion-time order, so the first slice does not promise severity-ranked or time-range queries.
- A row opens `/tenants/:tenant_id/monitoring/issues/:id`, with a safe summary, outcome, counts, owner, versions and paginated timeline. Occasion-only lists explicitly carry their occasion scope; EP rechecks it at every request. No global/raw-security diagnostic listing or raw payload export is offered.
- Acknowledge, assign, resolve and reopen use a session-bound form key plus the current expected version. Assignment currently takes the ID of an existing authorized administrator because EP has no scoped administrator picker contract yet. Resolution uses approved reasons rather than free text. None of these actions retries a business operation or proves technical recovery.
- Actions and explicit list/detail refreshes return in-context Turbo Streams. Filters are retained in refreshed results and focus is restored where possible. A stale version produces guidance to refresh; stopped/unavailable views and revoked access replace the protected monitoring region with an unavailable state. They never serve a stale view as successful current data.

This is request/response streaming, not a live EP subscription. Lists do not automatically reorder or continuously poll in the background; readers explicitly refresh. Browser operation guards handle feedback ordering; projection versions and EP guards remain authoritative for actions.

## Delivery evidence

TOM reports a new opaque delivery-attempt UUID and optional accepted business-command ID. A test/file write is recorded as an attempt only. SMTP success adds `delivery.provider_accepted`; a permanent SMTP rejection uses `delivery.rejected`, and other send failures use `delivery.unknown`. These reports contain no recipient, message body, magic-link secret or provider credentials. A provider-accepted report does not prove inbox delivery. Signed provider callbacks, bounce tracking and external-effect reconciliation are not yet implemented. No completion check automatically resends a message.

## Verification and remaining work

Run `bin/rails test`, `node --test test/javascript/monitoring_test.mjs`, `bundle exec rubocop -a`, `bin/rails zeitwerk:check` and `bundle exec brakeman --no-pager`. Node is needed only for the browser-logic unit tests. Rails tests block network and stub EP; JavaScript tests exercise delayed streams, proxy/network failures, navigation and bounded GET-only checking.

An isolated PostgreSQL/EP smoke test verified real sign-in, a controlled TOM view exception, scoped observation persistence, MV list/detail/timeline, versioned acknowledgment and streamed list refresh. The planted sensitive exception message was absent from EP details. No real external email was sent. The Playwright connector was unavailable for this implementation, so desktop/mobile visual and real-browser Turbo behavior still need verification; automated request and client-logic tests do not replace that check.

Independent collection/probes, a durable bounded spool, automatic alert delivery, configurable aggregation, reporting-source administration, a human-friendly assignee directory, richer restricted diagnostics, retention/erasure/backup automation and production load validation remain pending under [monitoring_plan.md](../../../monitoring_plan.md).
