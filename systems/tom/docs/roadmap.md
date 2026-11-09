# Roadmap

1. [x] Rails / Phlex / Tailwind shell without database dependencies.
2. [x] EP email-token sign-in and encrypted browser session.
3. [x] Tenant creation and authorized tenant overview with manual refresh.
4. [x] Current-grant tenant/occasion workspace query and returning-admin navigation.
5. [x] Return invitation/challenge delivery material through EP’s authorized backend API; move delivery/provider handling into TOM (replace EP mailboxes/workers).
6. [x] Clickable sign-in confirmation and invitation/recruitment return paths.
7. [ ] EP session revocation and production SMTP provider rollout.
8. [x] Occasion creation, tenant occasion list and detail views through EP.
9. [x] Tenant-admin invitations, intended-recipient acceptance, expiry and pending revocation.
10. [x] Occasion-admin invitations, scoped acceptance and direct occasion navigation.
11. [x] Explicit recruitment opening/closure, shareable intake and pending application queue.
12. [ ] Application review, vouching/qualification/safeguarding evidence and membership acceptance.
13. [ ] Expiry-review WorkItems, retirement and personal-data cleanup.
14. [ ] Application registration, scope enforcement and production operational validation.

15. [x] EP-backed monitoring sources/capture, scoped lists/timelines/actions and Turbo error/completion feedback.
16. [ ] Configure deployed monitoring sources, verify desktop/mobile Turbo in Playwright and add independent collection/probes, durable reporting and alert delivery.

## Monitoring operations (local implementation)

- Implemented locally: monitoring source/rule administration, named assignment, restricted diagnostics, explicit platform view, encrypted transport buffering and alert delivery worker.
- Deployment pending: independent collector hosts/paging, provider callbacks, browser matrix, approved retention/holds and representative capacity evidence; see ../../../docs/pending_details.md.

Completed: development sign-in links in the flash notice; existing confirmation and production delivery preserved.

Completed: optional monitoring setup details with source availability, a separate successful-worker heartbeat and direct scope-settings links.

Completed: standalone recruitment poster and receipt, visible signed-out privacy checkbox, and separated responsive privacy/CTA layout.
