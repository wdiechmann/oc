# Changelog

## 2026-10-19

Created database-free TOM using Rails 8.1.4, Ruby 3.4.4, Phlex 2.4 and Tailwind 4. Added EP email-token verification, encrypted HttpOnly sessions, tenant creation, tenant lookup and ready/pending/error screens. Added HTTP contract integration tests, CSRF enforcement checks and idempotency retry coverage. Copied the requested AGENTS.md unchanged from `~/src/karl_a/carla/AGENTS.md`.

Fixed browser form rejection by using `Referrer-Policy: same-origin`. Regression coverage verifies a valid same-origin CSRF submission succeeds and a foreign-origin submission remains blocked.

Added tenant-scoped occasion creation, occasion listing in the tenant overview, draft/closed detail views, UTC expiry review dates, optional self administration and recoverable duplicate-name validation. EP implements transactional occasion facts and parent guards, current authority checks, an independent projector/control and stream-aware outbox recovery. The UI still has no database.

Added tenant-admin prospect invitations, seven-day expiry, pending revocation and a recipient inbox with verified-email acceptance. EP atomically grants tenant access on acceptance, rechecks sponsor authority, serializes acceptance/revocation and queues private development notifications. Verified the owner-to-prospect flow in a real browser using an isolated database; 43 EP tests and 20 TOM tests pass, including a two-connection acceptance/revocation race. Production notification delivery and automated invitation privacy cleanup remain pending.

Added occasion-admin invitations using the shared EP lifecycle with parent-bound occasion scope, expiry, revocation and verified-recipient acceptance. Acceptance creates only an occasion-admin grant. TOM displays explicit scope, gates invitation controls using current EP tenant authority and retains authorized **Open occasion** navigation for accepted recipients. Scope isolation and concurrent accept/revoke are covered; existing tenant invitation contracts remain compatible.
