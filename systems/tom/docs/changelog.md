# Changelog

## 2026-10-19

Created database-free TOM using Rails 8.1.4, Ruby 3.4.4, Phlex 2.4 and Tailwind 4. Added EP email-token verification, encrypted HttpOnly sessions, tenant creation, tenant lookup and ready/pending/error screens. Added HTTP contract integration tests, CSRF enforcement checks and idempotency retry coverage. Copied the requested AGENTS.md unchanged from `~/src/karl_a/carla/AGENTS.md`.

Fixed browser form rejection by using `Referrer-Policy: same-origin`. Regression coverage verifies a valid same-origin CSRF submission succeeds and a foreign-origin submission remains blocked.

Added tenant-scoped occasion creation, occasion listing in the tenant overview, draft/closed detail views, UTC expiry review dates, optional self administration and recoverable duplicate-name validation. EP implements transactional occasion facts and parent guards, current authority checks, an independent projector/control and stream-aware outbox recovery. The UI still has no database.

Added tenant-admin prospect invitations, seven-day expiry, pending revocation and a recipient inbox with verified-email acceptance. EP atomically grants tenant access on acceptance, rechecks sponsor authority, serializes acceptance/revocation and queues private development notifications. Verified the owner-to-prospect flow in a real browser using an isolated database; 43 EP tests and 20 TOM tests pass, including a two-connection acceptance/revocation race. Production notification delivery and automated invitation privacy cleanup remain pending.

Added occasion-admin invitations using the shared EP lifecycle with parent-bound occasion scope, expiry, revocation and verified-recipient acceptance. Acceptance creates only an occasion-admin grant. TOM displays explicit scope, gates invitation controls using current EP tenant authority and retains authorized **Open occasion** navigation for accepted recipients. Scope isolation and concurrent accept/revoke are covered; existing tenant invitation contracts remain compatible.


## 2026-10-21

Added explicit recruitment opening and closure, published campaign/policy fields, a shareable verified-user expression-of-interest form and a pending application queue. EP atomically records lifecycle and application facts; closure/expiry and changed-policy guards override stale views. Applications create no membership or assignment. Browser verification covered owner opening, applicant sign-in return, submission, queue visibility and closure; separate-connection tests cover concurrent close/intake. Admission, safeguarding review and retention execution remain subsequent work.


## 2026-10-23

Clarified the application boundary: EP returns invitations/authentication challenge delivery material to an authorized calling backend through its API (potentially MCP later); TOM or another application delivers its messages. No separate delivery-acknowledgment or queue contract is required. EP-side mailboxes/delivery workers are explicitly documented as temporary existing code requiring refactoring; runtime behavior has not changed.


Refactored the delivery contract into runtime behavior: EP now returns protected, backend-bound magic challenges and invitation delivery material through API responses; its delivery adapters/workers are removed and obsolete pending jobs are cancelled by migration. TOM owns SMTP/private file delivery, clickable scanner-safe sign-in confirmation, invitation return paths and safe invitation-send retries. Added current-grant workspace navigation for returning admins, with no database or mail queue in TOM. All seven requested admin flows were verified through the API and browser, using TOM's own development transport. Production SMTP connectivity remains operator-configured.

Final validation: 65 EP tests and 33 TOM tests pass; all seven flows were exercised through TOM-owned mailbox links in an isolated browser/database setup. Private development backend credentials were provisioned separately for each app and are excluded from version control.
