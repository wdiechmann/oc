# Changelog

## 2026-10-27

Created VERA as a separate Rails 8.1.4 client under systems/vera. Added Phlex/Tailwind/Turbo shell, port 3001 development startup, database-free setup, fixed-origin EP readiness transport and application/dependency health checks. Authentication and tenant books remain next work.

Verified five Rails tests (21 assertions), RuboCop, Zeitwerk and Brakeman (zero security warnings/errors). Playwright checked desktop 1280×900 and mobile 390×844: local Turbo/Tailwind loaded, no horizontal overflow, and the home page had no console errors. VERA reached the running EP readiness endpoint successfully. Both bin/dev and bin/setup --skip-server were exercised locally; temporary servers were stopped.

## Thin EP sign-in — 2026-10-27

Added existing-identity-only email sign-in, explicit confirmation, private cookie session, current EP workspace overview and independent logout. Identity administration stays in TOM. Local setup provisions a separate VERA credential; EP stores the existing-identity binding and exposes current-session revocation. Submitted form failures stream inline. Browser rehearsal against isolated EP verified link delivery/confirmation, authorized tenant display, logout, mobile layout and EP-down form preservation with one canonical identity and TOM's original session still active.

## 2026-10-28 — Replaced sign-in links

Separated invalid/replaced challenge guidance from session-expiry errors, added newest-VERA-message guidance and cleared stale confirmation state when requesting a replacement or opening a malformed link. Diagnosed a local outbox link invalidated by a subsequent issue; identity and backend bindings remained valid. No challenge lifetime, replay protection or throttle changes. Twelve Rails tests (110 assertions) pass.

## 2026-10-29 — Tenant books

Added EP-backed draft book creation/list/detail, rename/reparent forms, explicit hierarchy, currency/authority/calendar setup and revision/freshness indicators. Added protected current state, tenant-local/cycle-safe parent validation, command receipts, ordered MV publication/recovery and metadata-only replay. Conflict and unknown-outcome handling preserves draft work; completion checks are GET-only. Development migration applied.

Browser rehearsal used an isolated EP database and fake identity: created a parent and two child books, renamed/reparented into three levels, rejected a cycle inline and preserved the selected draft, checked desktop/mobile overflow and removed stale content when the MV was stopped. Fixed a browser-only HTML pattern syntax issue found by the rehearsal. Financial posting, consolidation calculation and occasion associations are not activated by setup.

Verification: 102 EP tests, 18 VERA tests (148 assertions) and 51 TOM regression tests pass; RuboCop/Zeitwerk and Brakeman checks pass with zero security warnings/errors. Desktop 1280×900 and mobile 390×844 were inspected with no horizontal overflow. Temporary rehearsal services, database and fake sign-in message were removed; existing user servers/sessions were left untouched.
