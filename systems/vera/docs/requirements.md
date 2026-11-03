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

## Book-local VAT/category catalogues

Replace fixed chart dropdown choices with projected book-scoped catalogue entries. Explicit active configuration stewards initialize the former choices once, create entries, rename code/name and deactivate/reactivate them. Codes stay reserved case-insensitively within book/kind. Tenant administration/parent hierarchy confers no automatic mutation rights. Initialization adopts existing account string selections in an atomic accepted batch without changing their meaning or rewriting earlier facts. The chart is readonly until initialization, preventing blank uninitialized dropdowns from clearing legacy selections.

New account forms use stable VAT/category entry UUIDs. EP validates current scope/kind/active state under the same setup authority lock and setup revision as account writes. Existing inactive associations may remain or be cleared; new assignments are rejected. Catalogue edits do not rewrite account IDs, references, versions or historical snapshots. A subsequent explicit account save captures the current code/entry version for its new revision. Preserve entry history, conflict drafts, source/accepted lag, stopped-view behavior and original-receipt recovery. VAT labels introduce no rates or posting calculations.

## Reviewed chart CSV transfer

The chart offers whole-chart and current-filter export from one ready, revision-fenced EP snapshot, plus a template with a scoped demo header row (tenant_id, book_id, position 100, active true). Uploads are UTF-8 comma-, semicolon- or tab-separated CSV, optionally with BOM: at most 500 records, 32 columns and 2 MiB. Preserve identifiers as strings and quote multiline text. Spreadsheet users must import numbers/IDs as Text; CSV cannot carry cell types. A reversible apostrophe escape protects exported spreadsheet formula triggers while preserving chart formula text on reimport.

An explicit book steward uploads, maps columns and reviews additions/revisions/unchanged rows and errors before accepting. Name/position must be mapped; unmapped optional fields preserve existing values, mapped blank cells clear them. Match by stable account ID, otherwise posting number; missing rows never delete/deactivate accounts. Blank header/calculation IDs create rows. Validate the final chart including duplicate/reserved numbers, positions, current catalogue references and formula forward references/cycles. Show before/after values and forbid acceptance while any error remains. Reviews are private to identity/backend and expire after one hour. Acceptance is atomic and bound to a signed digest, setup revision and original idempotency key. A changed chart requires explicit re-review. Unknown acceptance blocks new mutations; check the original receipt before explicitly retrying its unchanged small pointer. Export excludes unsaved line drafts and is blocked while a line is dirty.

The upload and mapping forms offer “create type, vat- and category-codes”, unchecked by default. For the three supported account types, this proposes missing distinct VAT/category codes from mapped import values, using the code as its name; reuse existing codes case-insensitively. Show proposed catalogue creation before acceptance and commit it atomically with account changes. Preview must not write catalogue entries; reserved/invalid codes and inactive references remain errors.

Blank or unmapped account types are guessed and marked in review: a number implies posting; a formula, or an unnumbered row immediately following postings, implies calculation; other unnumbered rows start as headers. Explicit types always win. These guesses do not bypass validation: calculations still require valid formula text and posting rows require valid account numbers. The template demonstrates header; the form lists posting and calculation as the other supported types.

CSV upload detects comma, semicolon and tab separators and ignores completely empty spreadsheet rows before headers or between records. Nonblank records retain strict header/width checks and upload limits.

VAT and account categories are independent book-local catalogues. Accept descriptive Unicode values (1–120 trimmed characters, without control/format characters) in either; preserve full labels instead of requiring ASCII identifiers or splitting descriptions. Deduplicate and reserve codes separately by kind, and reject cross-kind account references.
