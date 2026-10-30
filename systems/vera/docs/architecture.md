# Architecture

VERA owns its web presentation and client session; EP owns canonical identity, authorization, accepted facts, transactional finance guards and query projections. The app intentionally excludes Active Record/Active Job/Action Cable and has no database configuration. No runtime dependency on TOM is introduced.

`HomeController → Views::Home::Index → Components::Layout` renders the static shell without calling EP. `EpHealthController → Ep::Client → EP /health/ready` provides dependency readiness using a fixed configured HTTPS origin or loopback HTTP origin, short timeouts, no redirect following and no automatic retries. A response must be 200 JSON with status ready. No browser credentials are forwarded. Authentication is implemented as described below; financial commands and monitoring-source registration remain next work.

Phlex uses explicit Views and Components autoload namespaces; Turbo and Tailwind assets are served locally. A content-security policy permits same-origin scripts/styles with a style nonce for Turbo, and arbitrary request parameters are filtered from logs. VERA uses its own Rails secrets and future backend credential; there is no shared TOM cookie/secret store. Production requires its own deployment secrets and HTTPS configuration.

## Thin sign-in

VERA POSTs /api/v1/auth/sign-in-links with its own backend credential. EP issues only for an active verified existing identity and binds the challenge to that identity and requesting backend. GET /session/verify stores the short-lived pending value in VERA's encrypted HttpOnly cookie; POST /session confirms through EP's existing verification API. Session rotation drops pre-login state; only the opaque EP session and expiry are retained. EP checks identity/session and current grants on protected calls. GET /me/workspaces provides current navigation, not a financial permission grant.

DELETE /api/v1/auth/session revokes only the presented session. VERA clears its cookie even if EP is unreachable, with an uncertainty notice. TOM's independent session remains valid. No SSO redirect protocol, shared cookie or duplicate invitation/recovery workflow is added. VERA delivers its own ephemeral sign-in message as the calling backend under the existing EP API handoff contract.

Local operator setup creates matching private configuration copies for EP's `vera` registration and VERA's own credential. Production uses deployment secrets and HTTPS application origins. Exceptions/parameters are sanitized and known form errors stream into vera-feedback. Full operational monitoring ingestion remains pending.

## Book context implementation

BooksController uses Ep::Client book API methods; Phlex book views/components hold only display data and unsaved form state. EP persists canonical setup events, protected book state and an outbox in one transaction. One tenant-local finance_books metadata stream orders hierarchy changes; future journals/payments are not serialized on that stream. Oban builds the incremental book MV. VERA's normal reads use that API projection and compare accepted/source revisions; no local database is introduced.

Forms carry a scoped per-session idempotency key and expected projected book version. EP revalidates current access and hierarchy under tenant-local locks. A cycle/stale edit stays inline with the draft preserved. Unknown transport outcomes retain the original command type/key for a user-initiated GET-only completion check; the check never repeats the mutation. Forbidden/stopped views do not masquerade as current data. This initial metadata slice provides explicit refresh, not cross-user push subscriptions.

Current tenant admins provision book context metadata; neither tenant/occasion nor platform monitoring roles are interpreted as finance posting/payment grants. Occasion-only admins have no tenant-book setup surface. Book-scoped stewards and occasion bindings are implemented below; broader finance grants and activation remain later work.

## Finance setup implementation

FinanceSetupController and Phlex components use the versioned EP setup API, documented in [the finance setup contract](../../ep/docs/finance-setup-api.md). Protected SetupState, Steward, Binding and Account rows enforce acceptance; a book-local lock serializes role changes and setup commands, while a tenant/occasion lock protects competing bindings. The initial AccountCreated event ID is the stable account ID. Account snapshots carry authenticated operator and backend application attribution. Tenant administration may assign/revoke roles, but configuration mutations require an explicit active book grant.

A separate finance_setup stream per book publishes accepted setup snapshots through outbox/inbox and SetupWorker to SetupView. The tenant's finance_setup MV control gates reads and delivery. SetupProjector supports safe rebuild, and pending-outbox recovery schedules setup workers. Routine account/binding display uses this MV; current grant/candidate checks are restricted control data. Workspace navigation includes only currently granted book links with running query controls.

Signed, expiring form tokens bind tenant/book/action/account and a random command key to the current VERA session. Accepted/source revisions distinguish pending projection. On a known conflict VERA re-renders the submitted draft above the latest projected accepted row; reapply uses current versions and a fresh key. On unknown outcome the encrypted session retains the original command/key/body and disables new saves until reconciliation. GET completion only reads the private receipt. After an unknown receipt, a separate CSRF-protected explicit retry submits the original stored body/key, never edited replacement fields. No local financial database or automatic transport retry is introduced.

## Chart pages and browser editor

ChartAccountsController reuses the existing signed command tokens, EP mutation/receipt handling and exact-original retry workflow, but renders a separate chart view. EP's GET setup/accounts endpoint filters/sorts the setup MV in canonical position order and returns at most 100 rows (50 by default), pagination totals and the initial VAT/category option labels. will_paginate wraps the remote page as a Collection without an Active Record dependency. Stable source revisions fence infinite-scroll requests, avoiding mixed-generation pages when rows move or change.

The locally served chart_editor module defines a native coa-editor custom element. It delegates line-edit/type-toggle and keyboard events, pauses infinite loading while a line is open, and uses IntersectionObserver plus same-origin GET Turbo streams to append pages and replace pagination controls. Normal will_paginate links remain available. Home/End and page keys can navigate to unloaded first/last/adjacent pages; inputs retain native editing keys. A changed revision stops appending while keeping the editor; stopped/revoked access clears the protected surface. Server-rendered conflicts preserve the draft above the newer accepted line. Acceptance can trigger read-only refreshes until projection catches up; mutations are never automatically retried.

EP stores VAT/category labels, canonical integer position, formula text and stable formula_refs. Its restricted arithmetic parser validates syntax/references and detects cycles without executing text. Number references bind to initial account event IDs; unchanged expressions remain pinned across renumbering. Stable UUID references support unnumbered calculations. Legacy event snapshots normalize heading/total row types and gap-spaced positions during replay; the schema migration preserves former number reservations and supplies no fictional calculated values.
