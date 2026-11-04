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

## 2026-10-30 — Book-scoped finance setup

Added explicit configuration-steward assignment/revocation per book, tenant-local occasion bindings and an initial CoA list/create/revise/deactivate/reactivate interface. Tenant administrators can inspect/assign roles; account/binding changes require an explicit steward grant, including for the administrator. Roles do not inherit through parentage or imply journal/payment authority. Accounts retain their AccountCreated event IDs, leading-zero string numbers, reserved former numbers and actor/application/revision attribution.

EP protects current setup and grant state under per-book locks, serializes competing occasion bindings, publishes setup snapshots through ordered outbox/inbox workers and exposes independent pending/stopped MV state, recovery and safe rebuild. VERA uses signed session-scoped forms and private receipts, preserves conflicting account drafts above the newer accepted row and offers explicit reapplication. New saves stay blocked during unknown outcomes; after checking the receipt, an explicit retry can submit only the stored unchanged original request/key. The development migration is applied; no steward grants are created automatically.

Verified 110 EP tests (including real concurrent account/binding transactions), 25 VERA tests (201 assertions), and 51 TOM regression tests. RuboCop and Zeitwerk pass. Brakeman's local scan reports zero errors/security warnings; the wrapper's online latest-version check was unavailable, so the installed scanner was invoked directly. Playwright checked sign-in, assignment, binding, leading-zero account creation, conflicting draft preservation/reapplication, unique DOM IDs and desktop/mobile layout without horizontal overflow, against a synthetic loopback EP fixture. Browser verification found and fixed a modern HTML pattern syntax issue. Temporary rehearsal services were stopped.

Remaining CoA package work includes periods, canonical account ordering/moves, formulas, rules/mappings and CSV import/export. No journals, payment execution or consolidated balances are activated.

## 2026-10-30 — Dedicated chart line editor

Moved the chart out of book role/occasion setup into its own page. Replaced account cards with compact Type/Number/Name/VAT/Category/Position/Formula lines, type-dependent controls, Enter edit/save, Escape cancel, native Tab/text-field navigation and list-focused arrows/Home/End/PgUp/PgDn. Added will_paginate over bounded EP chart pages, progressive infinite scrolling, source-revision fences, dirty-line navigation protection, focused saved-row recovery, explicit conflict comparison and local horizontal scrolling on narrow screens.

EP now protects unique integer positions, validates the initial VAT/category option labels, clears irrelevant fields by type, and stores restricted arithmetic formula text with stable account references and cycle/scope checks. Legacy heading/total snapshots normalize to header/calculation, keeping prior numbers reserved and deriving gap-spaced positions. Formula configuration does not execute code or calculate ledger balances. The local development migration is applied. The existing local VERA process was gracefully restarted to load will_paginate and its health endpoint returned 200. Other deployments must install the dependency and restart before using the chart.

Verified 113 EP tests, 29 VERA tests (234 assertions), 51 TOM regression tests, RuboCop, Zeitwerk and an installed Brakeman scan (zero errors/security warnings; online latest-version wrapper bypassed as previously documented). Playwright exercised all requested navigation keys across unloaded pages, 120-row infinite append without duplicate IDs, all type-specific visibility rules, header/calculation creation, VAT/category persistence, Enter saves, dirty draft protection, conflict reapplication, revision-change rejection and desktop/mobile overflow. Temporary browser fixtures used no real accounting records and were stopped after verification. The ignored VERA code graph was refreshed.

## 2026-10-30 — Book accounting periods

Added a separate accounting-period view and EP create/revise/open/close/reopen API. Inclusive ISO dates are protected against overlaps within a book, editable only while Draft and immutable after opening. Current active book stewards maintain periods; reopening also requires a separately assigned permission and a nonblank reason. Tenant administrators assign that permission explicitly, and steward revocation clears it. Registry/period versions, idempotency and current-authority checks protect all commands, including retries. Access loss during an uncertain retry retains the private original receipt key while clearing protected content.

Added an independent ordered event stream, period/state tables, period history MV, stopped/pending controls, outbox recovery and replay-only rebuild. State transitions take the period row's exclusive lock; the internal future-posting date guard holds a conflicting shared lock through its caller's transaction. A real PostgreSQL concurrency test proves closure waits for that guard and later guards reject the closed period despite a stale query projection. No journal API, book activation, balance check or external-ledger period execution is introduced. The local development migration is applied without granting reopening rights.

Verified 120 EP tests, 38 VERA tests (304 assertions), 51 TOM regression tests, RuboCop, Zeitwerk and the installed Brakeman scan (zero errors/security warnings; online latest-version wrapper bypassed as previously documented). Playwright exercised draft creation/correction, opening/date freeze, a lost close response and original receipt recovery without repeated closure, explicit reopening permission/reason/history, inclusive overlap rejection, preserved conflict drafts and desktop/mobile layout with unique IDs and no page overflow. Temporary browser fixtures used no real accounting records and were stopped after verification. Refreshed the ignored VERA graph.

## 2026-11-02 — Book VAT/category catalogues

Replaced fixed dropdown options with book-local event-backed VAT/category label entries, stable IDs/versions, rename/lifecycle controls, reserved former codes and actor/application/UTC history. Added a separate catalogue view, create/edit/deactivate/reactivate flows and structured chart options. New account forms submit entry UUIDs. EP shares the setup authority lock/revision across catalogue and account commands, validates scope/kind/current active state and rejects stale/concurrent assignments. Existing inactive associations can be retained/cleared without allowing new assignments.

A one-time explicit steward initialization adopts the former choices and existing account selections atomically, preserving account identities/meaning and earlier event payloads. The schema migration is applied locally but does not initialize user books. Chart editing is readonly until adoption; reads never seed data. Catalogue edits do not rewrite accounts. Existing compatibility API inputs remain supported as documented in the catalogue contract. VAT entries are labels, with no rates/calculation or new posting authority.

Verified 127 EP tests (including concurrent deactivation/assignment), 44 VERA tests (352 assertions), 51 TOM regression tests, RuboCop, Zeitwerk and the installed Brakeman scan (zero errors/security warnings; online latest-version wrapper bypassed as previously documented). Playwright checked explicit adoption of a legacy account, custom category creation, code/name rename, stable reference retention, inactive filtering/retention, account save with the new category, lost entry-save receipt recovery without replay, conflict draft reapplication and mobile layout with unique IDs/no page overflow. Temporary fixtures used no real accounting records and were stopped. Refreshed the ignored VERA graph.

## 2026-11-02 — Reviewed chart CSV transfer

Added ready-snapshot whole/filtered CSV export, empty templates and bounded upload → column mapping → before/after review → atomic acceptance. EP owns expiring private drafts, source/review digests, current role/revision/catalogue/formula validation and original receipts. Stable account identities, number strings, reserved numbers and missing rows are preserved. Final-state position swaps commit together; individual changed-row events project as one complete command even across worker page limits. VERA uses a small signed acceptance pointer and reconciles lost acknowledgements without repeating writes. No journals, balances or money movement are imported.

Browser rehearsal against a synthetic loopback EP covered upload/mapping/acceptance, export, invalid rows, stale revisions, lost acknowledgement/receipt recovery and dirty-editor export blocking. Desktop 1280×900 and mobile 390×844 had no page overflow; only deliberately injected HTTP errors appeared in the console. Temporary fixture services were stopped. Verification: 136 EP tests, 50 VERA tests (404 assertions) and 51 TOM tests (409 assertions) pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. The development migration adds private reviews and a deferrable account-position constraint without changing book/account data.

## 2026-11-03 — Scoped demo template and import code creation

CSV templates now include the tenant/book IDs, a demo header row, position and active flag. Added “create type, vat- and category-codes” to upload and mapping forms, with explicit review of unique missing VAT/category entries. New codes use their code as name and are committed with account changes in one version/digest-checked command; existing entries are reused and reserved/invalid/inactive references stay protected. Account types remain header/calculation/posting. Preview uses provisional entries without catalogue writes, and catalogue history/rebuild/receipt replay remain supported.

Added conservative type inference for blank/unmapped type fields, with explicit choices retained and guesses marked in review. Numbered rows are posting; formula rows and unnumbered rows after postings are calculation; remaining unnumbered rows are headers. Calculation formulas still require validation before acceptance.

Verification: 139 EP tests and 51 VERA tests (416 assertions) pass; RuboCop and Zeitwerk pass; Brakeman reports zero warnings/errors. Browser rehearsal checked the downloaded demo values, checkbox retention, deduplicated code proposals and desktop/mobile layouts with no console errors. No database migration is required.

## 2026-11-03 — Regional CSV upload

Fixed semicolon/tab spreadsheet imports and skipped completely empty rows, including a separator-only row before the header. Reproduced the reported Kontoplan.csv upload and verified all 231 records parse as 16 string columns. Duplicate/blank headers and inconsistent nonblank row widths remain errors.

Verification: 52 VERA tests (421 assertions), RuboCop and Zeitwerk pass. Playwright uploaded the reported file against a synthetic EP and reached column mapping with all 231 records.

## 2026-11-03 — Descriptive VAT and category values

Removed the shared ASCII-only code restriction responsible for 13 VAT errors and one Danish category error in the reported file. Manual catalogue commands and import proposals now share a bounded Unicode text validator; full values are preserved. VAT and account categories remain independent by kind for matching, deduplication, reservations and references. Import guidance and review labels make that distinction explicit.

Verification: 140 EP tests and 52 VERA tests (421 assertions), RuboCop and Zeitwerk pass. The reported file produces 13 VAT and 4 category proposals with zero catalogue-code errors in a non-writing test-database check. Playwright verified separately labelled VAT/category proposals and mobile layout against synthetic EP. No migration is required.

## 2026-11-03 — Replace chart by default

Added replacement and explicit merge modes. Replacement validates positions against the proposed chart, retains matching identities and retires omitted accounts in the same version/digest-checked command. Preserved retired numbers/positions/formulas/references and immutable earlier events; existing numbers remain reserved and may only return on their original IDs. Added AccountRetired/AccountRestored projection/rebuild support and a paginated read-only Retired accounts view. Legacy import reviews stay merge until explicitly re-reviewed as replacement. The migration adds retirement metadata and scoped position uniqueness without retiring any user accounts.

Verification: 144 EP tests, 55 VERA tests (450 assertions) and 51 TOM regression tests pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Browser rehearsal checked replacement/merge collision differences, retained/retired review, explicit acceptance, current-only export, read-only retired history and desktop/mobile fit with no console errors. The development migration is applied. No real book has been replaced by verification.

## 2026-11-03 — Native reviewed chart ordering

Added Reorder / rebalance with focused-row and selected-block movement, insertion before another account, Shift-click range selection, keyboard controls and draft navigation protection. Review shows deterministic 100-step before/after positions; explicit acceptance uses a private signed review, current authority, complete membership, revision and digest checks. Position-only writes preserve identities, account fields, catalogue snapshots and formula references. Atomic account events use the existing outbox/projection/rebuild flow, and unknown outcomes retain original receipts/retries. Native and CSV reviews are purpose-isolated in existing expiring storage. No database migration is required.

Verification: 153 EP tests, 61 VERA tests (502 assertions) and 51 TOM regression tests pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Browser rehearsal checked full-chart scope from a filtered chart, Shift-click blocks, move/insert/keyboard controls, dirty navigation, stale-draft preservation, rebalance and moved-order acceptance, original-receipt recovery, access-revocation clearing, and desktop/mobile fit. Only deliberately injected HTTP failures appeared in the console. Temporary fixture services were stopped; no real book was reordered.

## 2026-11-04 — Effective-dated VAT rules

Added explicit dated rates, deductible VAT shares, input/output/reverse-charge/no-VAT treatments and signed reporting mappings on VAT entry UUIDs. Shared setup authority/revision/idempotency guards serialize overlapping ranges and retain rule history through projection/rebuild and chart changes. Read-only protected quotes expose exact integer rounding, credit signs, deductions and reporting sums; no statutory rates or postings are inferred from labels. VERA adds rule forms/history, conflict draft reapplication and original-receipt recovery. The migration creates storage without seeding any user rules.

Verification: 160 EP tests, 66 VERA tests (538 assertions) and 51 TOM regression tests pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Browser rehearsal checked explicit blank rates, dated rule creation, overlap rejection, preserved conflict drafts, reapplication, original-receipt recovery, rule history, readonly access and desktop/mobile fit. Only deliberately injected HTTP errors appeared in the console. The development migration is applied; no real VAT rules or statutory presets were created.

## 2026-11-04 — Sourced Danish VAT presets

Added 16 explicitly selected Danish VAT drafts with reviewed conditions, source links, versioned accepted provenance and customization tracking. Existing labels can suggest a unique active VAT entry but never accept a rule; dates require review. Imported-goods rules require the customs-assessed VAT amount. Preset data is configuration assistance, not automatic tax filing.

Verification: 162 EP tests and 67 VERA tests (553 assertions); RuboCop and Zeitwerk pass, with zero Brakeman warnings/errors. Playwright checked preset selection, blank dates, matched/unmatched VAT entries, source links, explicit save and desktop/mobile fit against synthetic data. The provenance/assessment migration is applied; existing books receive no automatic rules. The VERA code graph was refreshed.

## 2026-11-04 — Read-only chart formula preview

Added a dedicated formula rehearsal page with explicit test balances, stable-ID reference breakdowns, exact nested arithmetic and clear per-row errors. Shared parsing preserves the accepted grammar; source revision, authority, input and complexity guards live in EP. No configuration or ledger writes and no persistent test balances.

Verification: 172 EP tests and 71 VERA tests (588 assertions) pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Playwright checked pinned renumbered references, inactive account labels, explicit missing-balance errors, signed fractional rounding and desktop/mobile fit with synthetic data. The VERA code graph is refreshed. No migration or real accounting data changes were required.

## 2026-11-04 — Reviewed report definitions and mappings

Added named report definitions with header/mapping/total lines, stable IDs and reserved codes, signed posting mappings and pinned formula references. Private expiring reviews show before/after and coverage warnings before atomic setup acceptance; history retains account labels/cutoffs through chart replacement. Exact historical test previews never persist balances or post journals. Unknown outcomes use the original small review pointer and receipt.

Verification: 179 EP tests and 77 VERA tests (634 assertions) pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Playwright rehearsed creation, adding lines, coverage review, explicit acceptance, signed exact previews, report revision and historic-version reopening with desktop/mobile fit against synthetic data. The storage migration is applied and the VERA code graph refreshed. No real report definitions or financial transactions were created.

## 2026-11-04 — Reviewed unposted journal drafts

Added dated multi-line debit/credit preparation with explicit references and VAT quotes, balanced/open-period/account checks and deliberate saving of unfinished drafts. Separate protected draft/registry state, typed events and controlled query/history projection preserve corrections and validation cutoffs. Private expiring reviews and original-pointer receipts guard acceptance and recovery. No ledger, approval, posting or external execution is activated.

Verification: 187 EP tests and 83 VERA tests (686 assertions) pass; RuboCop/Zeitwerk pass and Brakeman reports zero warnings/errors. Playwright checked balanced draft creation with separate VAT quotes, explicit saving of an unbalanced correction, preserved historical amounts, absence of posting controls and desktop/mobile fit against synthetic data. Source-lag tests preserve readable unsaved entries and show newly saved drafts as pending until projected. The storage migration is applied and the VERA code graph refreshed; no real journal drafts or financial transactions were created.

## 2026-11-04 — Paired work-journal rows and traceable enclosures

Journal creation now takes header fields only and opens the line editor immediately. Added paired account lookup, localized decimal entry, exact gross/net VAT previews, stable book-wide posting IDs with rollback/retry/void retention and private PDF/image enclosures. Account VAT inclusion defaults are editable in the chart, survive import/reorder, and can be overridden per posting or restored with Use account default. Existing unspecified defaults are preserved. Work remains a draft for the later authorization/verification/posting workflow.

Verification: 194 EP tests and 87 VERA tests (731 assertions) pass; RuboCop/Zeitwerk and JavaScript syntax checks pass, with zero Brakeman warnings/errors. Playwright checked header-only creation, keyboard slash lookup and blur preservation, comma amount/VAT preview, row save, enclosure staging/binding/download, void retention, numbering continuing in another journal and desktop/mobile grid fit. Number-allocation tests cover rollback, retries, book isolation, header edits and blocked row removal. Migration applied; no real business journals or enclosures were created. VERA code graph refreshed.

## 2026-11-04 — Journal column order and credit amount

Moved posting ID first and VAT inclusion into its own column immediately after debit amount. New entry rows and newly saved rows prepend the list. Added a localized editable credit amount, calculated by EP from debit and VAT configuration, with a manual override/reset. Existing posting numbers and saved credit values remain stable.

Verification: 194 EP tests and 89 VERA tests (743 assertions) pass. Browser checks cover VAT included/excluded credit prefill (125,00 → 125,00 or 156,25), manual override/reset, newest-first saves, ten grid columns and mobile overflow containment. RuboCop, Zeitwerk and JavaScript syntax checks pass; VERA graph refreshed.

## 2026-11-04 — Compact VAT cells and full-width journal

Both VAT headers now read VAT. Inclusion cells contain only a checkbox; calculated VAT cells show only the localized amount (or zero), with explanations in hover/accessibility text. Journal pages use full width and the grid contracts reference, accounts, then amounts as space decreases. Pending/error VAT stays distinguishable.

Verification: 89 Rails tests (751 assertions), RuboCop, Zeitwerk and JavaScript syntax checks pass. Playwright checked checkbox-only cells, numeric VAT and hover explanations, and responsive column priority at 1920, 1440, 1280, 1150, 1080, 1024 and 375 pixels without page overflow.

## 2026-11-04 — More menu for journal row actions

Moved journal row actions and VAT/credit resets behind a vertical-dot More icon, following Carla’s SVG/context-menu and shared-dialog focus conventions. Added reusable VERA SVG and context-menu components, native popover positioning, keyboard navigation, outside dismissal and focus return. Menus retain the existing row form and financial commands; the action column is narrower.

Verification: 89 Rails tests (760 assertions), RuboCop, Zeitwerk and JavaScript syntax checks pass. Playwright checked state-specific actions, keyboard edit, Enter save, Escape without cancelling edits, cancel, void/restore, outside dismissal and mobile menu bounds. VERA graph refreshed.
