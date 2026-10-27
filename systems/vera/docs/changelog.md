# Changelog

## 2026-10-27

Created VERA as a separate Rails 8.1.4 client under systems/vera. Added Phlex/Tailwind/Turbo shell, port 3001 development startup, database-free setup, fixed-origin EP readiness transport and application/dependency health checks. Authentication and tenant books remain next work.

Verified five Rails tests (21 assertions), RuboCop, Zeitwerk and Brakeman (zero security warnings/errors). Playwright checked desktop 1280×900 and mobile 390×844: local Turbo/Tailwind loaded, no horizontal overflow, and the home page had no console errors. VERA reached the running EP readiness endpoint successfully. Both bin/dev and bin/setup --skip-server were exercised locally; temporary servers were stopped.

## Thin EP sign-in — 2026-10-27

Added existing-identity-only email sign-in, explicit confirmation, private cookie session, current EP workspace overview and independent logout. Identity administration stays in TOM. Local setup provisions a separate VERA credential; EP stores the existing-identity binding and exposes current-session revocation. Submitted form failures stream inline. Browser rehearsal against isolated EP verified link delivery/confirmation, authorized tenant display, logout, mobile layout and EP-down form preservation with one canonical identity and TOM's original session still active.
