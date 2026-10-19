# Changelog

## 2026-10-19

Created database-free TOM using Rails 8.1.4, Ruby 3.4.4, Phlex 2.4 and Tailwind 4. Added EP email-token verification, encrypted HttpOnly sessions, tenant creation, tenant lookup and ready/pending/error screens. Added HTTP contract integration tests, CSRF enforcement checks and idempotency retry coverage. Copied the requested AGENTS.md unchanged from `~/src/karl_a/carla/AGENTS.md`.

Fixed browser form rejection by using `Referrer-Policy: same-origin`. Regression coverage verifies a valid same-origin CSRF submission succeeds and a foreign-origin submission remains blocked.
