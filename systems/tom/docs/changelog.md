# Changelog

## 2026-10-19

Created database-free TOM using Rails 8.1.4, Ruby 3.4.4, Phlex 2.4 and Tailwind 4. Added EP email-token verification, encrypted HttpOnly sessions, tenant creation, tenant lookup and ready/pending/error screens. Added HTTP contract integration tests, CSRF enforcement checks and idempotency retry coverage. Copied the requested AGENTS.md unchanged from `~/src/karl_a/carla/AGENTS.md`.

Fixed browser form rejection by using `Referrer-Policy: same-origin`. Regression coverage verifies a valid same-origin CSRF submission succeeds and a foreign-origin submission remains blocked.

Added tenant-scoped occasion creation, occasion listing in the tenant overview, draft/closed detail views, UTC expiry review dates, optional self administration and recoverable duplicate-name validation. EP implements transactional occasion facts and parent guards, current authority checks, an independent projector/control and stream-aware outbox recovery. The UI still has no database.
