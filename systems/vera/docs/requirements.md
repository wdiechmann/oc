# Requirements

VERA is a separate client for financial control, accounting and settlement. It must use EP APIs for accepted data and current authorization, with no local business database. Books and their nesting are financial contexts using the same underlying tables and associations, as specified in ../../finance.md.

The initial foundation provides a public Phlex/Tailwind shell, locally served Turbo and separate application/dependency health checks. It must start independently of EP and coexist with TOM on a different port. Financial functionality requires a subsequent authenticated, scoped EP contract.

Sign-in is a thin EP-backed operation for an existing identity. Signup, invitations, recovery and identity administration remain in TOM. Require backend-bound single-use links, explicit confirmation, generic unknown/throttled responses, a private VERA session, current EP workspace checks and own-session revocation. No duplicate identity store or shared TOM cookie/credential is permitted.

## Tenant books — first delivery

Active tenant administrators can create/list/view draft book contexts and revise names/parent relationships through EP. All levels use the same schema. Require tenant-local unique codes, current session/grants, cycle-safe hierarchy, expected book versions, idempotency and no local authoritative persistence. This bootstrap authority covers metadata only; financial permissions remain separate. Provide pending/stopped query states, protected-region clearing after revocation and lost-response receipt reconciliation.

## Book-scoped finance configuration

Tenant administrators explicitly assign/revoke configuration stewards for individual books, including themselves. Administration alone permits inspection/role assignment, not account or binding changes. Stewardship neither inherits across parent/child books nor grants approval/posting/payment authority. Current identities, sessions, tenant status and protected grant state govern every command before replay.

A steward can bind/unbind this tenant's occasions and list/create/revise/deactivate/reactivate accounts. An occasion has at most one applicable book; several occasions may share it. Moving requires explicit release from the previous book. Account IDs equal their AccountCreated event IDs; numbers are strings with leading zeroes, and old/inactive numbers remain reserved. Header/calculation/posting rows are distinct; formula configuration is described below, while ledger-result calculation remains later reporting work. Protect setup/account versions and use idempotent commands with private receipts. Preserve conflicting drafts above the newer accepted account, with actor/application/revision and explicit reapplication. Unknown saves block new changes; completion checks never repeat writes. An explicit retry after checking uses only the original unchanged command and key.

## Dedicated chart line editor

The chart has its own book page, separate from steward/occasion setup. Show compact rows in Type → Number → Name → VAT → Category → Position → Formula order. Types/VAT/category are dropdowns; number/name are strings, formula is text and position is a positive integer independent of account number. Header shows only name/position; calculation shows name/position/formula; posting shows number/name/VAT/category/position. Clear irrelevant fields in EP, reserve prior numbers, validate formula references/cycles and retain stable identities.

Enter opens/saves a line; Escape cancels. With list focus, arrows move rows, Home/End select first/last chart rows and PgUp/PgDn change pages. While editing, preserve native text/dropdown navigation and Tab; Shift+Enter inserts a formula newline. Only one dirty line may be edited at a time. Paginate via will_paginate over EP's bounded chart pages (50 rows), with ordinary links and progressive infinite append. Every appended page must match the original ready projection revision; fail closed on changed/stopped/revoked data. On small screens the chart region scrolls horizontally without widening the page.

## Accounting periods

Provide a separate book period view with strict inclusive date-only ranges in the book calendar/timezone. Draft periods may be renamed/re-dated if they remain nonoverlapping. Opening freezes name/dates; only Open → Closed and explicitly authorized Closed → Open transitions follow. Require current registry/period revisions, idempotent commands and no local business database. Reopening requires both active book stewardship and separately assigned reopening permission, plus a nonblank 1–500-character reason; tenant administration alone cannot reopen. Revoking stewardship clears reopening permission.

EP must serialize overlap checks and role-sensitive acceptance, and transitions must contend on protected current period row locks. Future journal handlers must check book activation/accounting authority and financial authority before holding the period's open-date guard through ledger/event commit. A query MV never authorizes posting. Expose accepted/source lag and stopped states, actor/application/UTC history and private receipt reconciliation. Preserve drafts even when a newer transition makes their original editing form unavailable. External-authority periods are local preparation controls without external ledger execution.
