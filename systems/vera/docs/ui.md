# UI

The public home page introduces VERA and links to **Sign in** at /session/new. Use the same email as the existing identity managed in TOM; there is no VERA signup, invitation or recovery UI. **Open TOM** links to the configured TOM origin for those tasks.

Request a link, open its VERA URL and press **Continue to VERA**. In development the link is in VERA's private tmp/outbox file. GET alone does not redeem it. A generic notice covers unknown/throttled addresses. EP/delivery failures render inline, preserving the email form; tokens never appear in the rendered page.

After sign-in, the home page lists only the current tenants/occasions returned by EP, or explains that no authorized workspaces are available. These are navigation contexts; financial commands still require current explicit authority. **Sign out** clears VERA and revokes its EP session independently from TOM. If EP cannot confirm revocation, show that fact rather than claim global logout.

Desktop/mobile pages use Phlex/Tailwind, local Turbo, keyboard/touch form controls and status text. Book setup follows the current package in ../../system_2_plan.md.

A newly issued VERA challenge invalidates earlier VERA links; TOM links are backend-bound and cannot confirm a VERA session. Open the complete URL from the newest VERA message. Challenge rejection now explains replacement/use/expiry separately from an expired authenticated session and clears the rejected pending challenge. Requesting a replacement clears old confirmation state.

## Tenant books

After sign-in, **Open books** appears on each tenant-administrator card. The book registry identifies the tenant, displays roots/children with their parent and depth, and reports source/latest accepted revisions. **Create book** opens name/code, initial supported currency, accounting authority, timezone, financial-year start and optional parent fields. All books start Draft. Neither selecting External nor creating a parent starts an adapter or consolidation calculation.

Open a book to view its fixed initial setup and edit its name/parent. Codes and currency/authority/calendar are fixed in this slice. EP rejects unavailable/foreign parents, cycles and stale revisions. Inline feedback preserves the submitted form; a known conflict requires review/refresh. If a save response is lost, use **Check completion** before another submission. If the projection is pending, refresh and wait for the accepted revision before editing. If serving is stopped or access revoked, the protected view is unavailable rather than stale-successful.

Book hierarchy is context nesting. Accounting periods, extended CoA rules/imports, full finance-role delegation, live cross-user subscriptions and monetary functionality follow later; a book named SL2030 is not automatically associated with the SL2030 occasion.

## Roles, occasions and accounts

Open a tenant book and choose **Roles, occasions and accounts**. Tenant administrators can inspect its chart and explicitly assign/revoke configuration stewards, including themselves. The initial identity selector lists active existing tenant/occasion administrators and current stewards; the API also accepts a known existing verified identity UUID. No identity/invitation workflow is added. A steward sees a direct **Configure book** workspace card without gaining tenant-wide book administration.

Within that book, stewards link/unlink occasions. Accounts are maintained on the separate line editor described below, with actor/application/revision shown when a conflicting accepted row needs comparison. A book name does not establish an occasion association. Accounting periods, journals and ledger-result calculations remain later work.

Pending views disable editing until refresh catches up. Conflicts preserve the submitted draft above the newer accepted row and offer **Reapply draft** with current versions. A lost response offers **Check completion**, blocks new changes and never infers failure from a missing receipt. After an unknown receipt, **Retry original request** explicitly sends the unchanged original body/key, safely deduplicated by EP. Stopped views/revoked access replace the protected region. Drafts are not autosaved across navigation.

## Chart of accounts — separate line editor

Choose **Chart of accounts** from the book, or **Open chart of accounts** from roles/occasion setup. Each compact line has **Type – Number – Name – VAT – Category – Position – Formula** plus actions. Click Edit or focus a row and press Enter. Header exposes name/position, calculation exposes name/position/formula, and posting exposes number/name/VAT/category/position. Type changes hide/disable irrelevant inputs; EP clears their accepted values. Position changes canonical ordering, independently from account number. VAT/category dropdowns come from the book’s catalogues. Their initial choices are adopted once through the catalogue view described below, without tax-rate behavior.

Press Enter to save from a text/position/formula field (Shift+Enter allows a formula newline), or use Save; Escape/Cancel resets the line. Native selects keep Enter/arrow behavior. List-focused ↑/↓ move rows, Home/End go to the first/last chart row and PgUp/PgDn go to the adjacent page. Home/End/arrows in text fields keep normal caret behavior. Save/cancel a dirty line before navigating away or editing another. Account status remains an auxiliary control on the open line.

Pages contain 50 rows, with will_paginate links and automatic loading near the end. Infinite scroll appends only matching source revisions. If another user changes the chart, appending stops and asks for refresh, preserving the current list/editor. A pending accepted view refreshes through read-only requests until ready. Narrow screens scroll the chart region horizontally. Conflict drafts stay above the newer accepted row for explicit Reapply.

Formula examples: `[0010] + [0020]` or `([0010] - [0020]) * 0.25`. **Copy ref** copies `[@stable-account-id]`, useful for referencing an unnumbered calculation. Scope/reference/cycle validation runs in EP; displaying computed ledger results is later reporting work. No draft is autosaved across a full reload.

## Accounting periods

Open **Accounting periods** from a book, its roles/occasion setup or its chart. Create a named Draft with inclusive start/end dates. **Correct draft dates** edits a Draft only; after **Open period**, name/dates are frozen. **Close period** closes an Open period. A closed period only offers **Reopen period** to an active steward with separately granted reopening permission, and requires a reason. Tenant administrators grant/revoke that permission for existing stewards under **Roles and occasions**. Reassigning a revoked steward does not restore an old reopening grant.

Expand **Period history** for each accepted creation/revision/open/close/reopen, its dates, actor, backend application, UTC timestamp and reopening reason. Compare a preserved date draft above newer accepted metadata before explicitly reapplying it; if a concurrent opening makes date correction unavailable, the submitted draft remains readable instead of offering an invalid edit. Pending projections disable changes until **Refresh periods** catches up; stopped/revoked views clear the protected surface. Lost responses use **Check completion** and, after an unknown receipt, explicit **Retry original request** with the stored unchanged body/key.

These controls create no journals or balances. For an external-authority book the view explicitly labels its periods as local preparation controls and does not open/close the external accounting system.

## VAT and category catalogues

Open **VAT and categories** from the book, setup or chart. An assigned configuration steward first presses **Initialize catalogues** once per book. This adopts the former three VAT and five category labels, binding existing account selections to stable IDs in one accepted batch. Chart editing stays disabled until adoption is projected; inspect existing rows and refresh the catalogue view if its status is pending.

Create VAT/category entries with code and name. **Edit entry** renames code/name or switches Active/Inactive; kind and stable ID remain fixed. Former codes remain reserved, and **Entry history** shows accepted code/name/status, actor/application and UTC timestamp. Known conflicts retain the draft above the newer accepted entry for explicit reapplication. Lost responses use the original private receipt and exact-original retry, with new changes blocked during uncertainty.

The chart displays current catalogue labels and submits UUID selections. Inactive entries remain visible/retainable on their existing accounts and are omitted from choices for new associations. Clearing a selection is explicit. Renaming/deactivation does not silently rewrite accounts or old history. The VAT catalogue stores classification labels only; rates, tax calculations and posting rules are later work.

## Chart CSV

The chart toolbar links Export accepted chart, Export filtered chart (when searching), CSV template and Import CSV (for stewards). Dirty line edits block download links. Downloads contain accepted data from the displayed revision, never unsaved edits. The import page explains bounds, Text identifiers, matching and missing-row semantics. Upload leads to explicit column mapping with a three-record sample; a review then shows create/revise/unchanged/error counts, expandable before/after rows and row/chart errors. The accept button appears only for a valid, unconsumed review and submits its signed digest/revision. Mapping may be revised without account writes. Stale/expired review errors link back to chart/review; unknown acceptance uses existing Check completion and original-request retry controls. Wide sample tables scroll inside their region on mobile.
