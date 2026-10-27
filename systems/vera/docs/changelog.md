# Changelog

## 2026-10-27

Created VERA as a separate Rails 8.1.4 client under systems/vera. Added Phlex/Tailwind/Turbo shell, port 3001 development startup, database-free setup, fixed-origin EP readiness transport and application/dependency health checks. Authentication and tenant books remain next work.

Verified five Rails tests (21 assertions), RuboCop, Zeitwerk and Brakeman (zero security warnings/errors). Playwright checked desktop 1280×900 and mobile 390×844: local Turbo/Tailwind loaded, no horizontal overflow, and the home page had no console errors. VERA reached the running EP readiness endpoint successfully. Both bin/dev and bin/setup --skip-server were exercised locally; temporary servers were stopped.
