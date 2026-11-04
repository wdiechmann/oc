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

The chart toolbar links Export accepted chart, Export filtered chart (when searching), CSV demo template and Import CSV (for stewards). Dirty line edits block download links. Downloads contain accepted data from the displayed revision, never unsaved edits. The import page explains bounds, Text identifiers, matching and missing-row semantics. Upload leads to explicit column mapping with a three-record sample; a review then shows create/revise/unchanged/error counts, expandable before/after rows and row/chart errors. The accept button appears only for a valid, unconsumed review and submits its signed digest/revision. Mapping may be revised without account writes. Stale/expired review errors link back to chart/review; unknown acceptance uses existing Check completion and original-request retry controls. Wide sample tables scroll inside their region on mobile.

Templates now contain a single `demo` header row with tenant/book IDs, position 100 and active true. Upload and mapping forms expose the exact label “create type, vat- and category-codes”; selection carries into mapping, where users can change it before review. The explanation retains header/calculation/posting types and limits code creation to unique missing VAT/category codes. Review lists every proposed catalogue entry alongside account changes.

The template demonstrates header; type guidance lists posting and calculation. Type mapping is optional; blank types are guessed from number/formula/block position and visibly marked on review rows. Explicit types win, and missing formulas or other validation failures still disable acceptance.

CSV upload detects comma, semicolon and tab separators and ignores completely empty spreadsheet rows before headers or between records. Nonblank records retain strict header/width checks and upload limits.

Import guidance distinguishes VAT descriptions (Dansk salgsmoms, UEUV - Varesalg EU) from account categories (Aktiv, Passiv, Indtægt). Review labels proposed entries as VAT or account category. Manual catalogue code inputs accept up to 120 Unicode characters without the former ASCII-only pattern.

Upload/mapping includes Import mode: Replace chart (default) or Merge into existing chart. Review states the mode, retained count and retire count, expands retirement before/after rows alongside incoming changes, and names the replacement button Accept chart replacement. Old drafts retain Merge until explicitly changed. Chart navigation links Retired accounts and Current chart; retired view shows preserved rows without edit/import/export controls. Search, keyboard/page navigation and infinite scroll retain the selected history scope.

If another steward replaces a chart while a line is being edited, a rejected save preserves the submitted draft as text even when its account has left the current chart. It offers no automatic reapplication to a retired row.

## Reorder / rebalance

The current chart toolbar links Reorder / rebalance. Its complete list includes inactive accounts and supports checkbox blocks, Shift-click ranges, focused-row moves, Move up/down/first/last and Insert selection before another account. Row focus uses arrows/Home/End/PgUp/PgDn; Space selects and Alt+arrows/Home/End moves. Inputs keep native behavior. A live status and draft position arrows explain pending changes. Review order and Review position rebalance both open a before/after review before Accept reviewed order. Dirty navigation is blocked until review/discard; a preview conflict/network failure leaves the draft in the editor. Revoked access clears protected editor content. Unknown acceptance uses Check completion and explicit unchanged original-request retry. Whole-chart order is independent of the normal chart’s page/search filters; retired history cannot be reordered.

## Effective VAT rules

VAT/category catalogues link to Effective VAT rules. Cards show the linked VAT label, inclusive dates, treatment, VAT/deductible percentages, reporting contributions, lifecycle and accepted history. Forms require explicit treatment/rates, offer four optional mapping rows (box, component, sign), and keep a rule on its original VAT entry. Dates, overlap/reference errors and newer revisions retain the submitted draft for explicit comparison/reapplication. Source lag, missing stewardship or unknown acceptance suppress edits. Completion/retry links use the VAT-rule route and original command body/key. These forms define configuration; they create no journals or payments.

## Danish VAT preset drafts

Effective VAT rules offer 16 versioned Danish templates, including domestic VAT, qualifying restaurant/hotel deductions, EU/non-EU trade and domestic reverse charge. Selection fills an editable draft with source links and usage conditions; effective dates remain blank. Only a unique active alias match suggests a VAT entry, with UEUV distinct from UEUV2. Importing labels never accepts tax rules. Accepted rules and histories pin the source version and track customized values. Imported-goods assessment requires an explicit customs-statement VAT amount rather than calculating from supplier net. EP owns validation, calculation and provenance; VERA has no local policy database. See ../../ep/docs/danish-vat-presets.md.

## Chart formula preview

The chart links to Formula preview. The page lists current posting rows with labeled signed whole-minor-unit test inputs and current calculation formulas with pinned bindings. Preview formulas shows rounded results plus exact fractions, direct reference breakdowns and expandable underlying posting balances; errors identify the related account where available. Blank inputs remain unknown, inactive rows are marked, and a chart-revision conflict preserves entered balances for comparison with the current chart. Tests use accepted saved formulas; unsaved chart line edits are excluded. The layout wraps long formulas/references on small screens.

## Versioned report definitions

The chart links to Report definitions. Create/edit report names and lifecycle, then add/remove line fieldsets with code, name, type, position, mapping sign, total formula and multiple posting-account selections. Add report line preserves the request-local draft without accepting changes. Reviewed pages show before/after definitions, source revision/expiry and coverage warnings, then require Accept reviewed report. Retired selected accounts remain visible as unavailable rather than silently clearing. Index history links open exact accepted revisions and source labels; separate saved/current coverage explains chart drift. Test previews show signed exact/rounded values and expandable account/line breakdowns. Blank balances are unknown, authority/lag suppress edits, and original-receipt recovery retains only the acceptance pointer.

## Unposted journal preparation

The chart links to Journal drafts. Create/edit name, date, reference and line fieldsets with account, debit, credit, line reference, explicit VAT selection, signed net base and optional import-statement assessment. Add/remove lines preserves request-local drafts. Review shows previous/current data, exact totals/difference, account errors, period eligibility, VAT rule/amount evidence and partial reporting warnings. Save reviewed draft or Save draft with issues always means unposted. Index/history links preserve saved revisions; context changes show stale-validation notices. Missing retired selections stay visible for correction. Pending/stopped/revoked states suppress edits; unknown acceptance offers original receipt check/unchanged retry. Source lag after accepted creation shows pending rather than an erroneous missing-draft page.

## Work-in-progress paired journal editor

The saved journal opens directly into a compact horizontally scrollable line editor. Header details remain editable separately. Slash lookup shows active posting-account number/name options with Up/Down/Enter/Escape and clears stale hidden identities when text changes; popovers escape the grid clipping region. Decimal amounts follow the form locale, while VAT is recalculated by EP from selected accounts and amount. VAT inclusion follows the selected account default, with a per-posting checkbox override and Use account default reset. Unspecified or conflicting defaults remain visible for correction. Enter saves a row, Escape cancels, and dirty rows block other saves/navigation. Posting IDs appear only after save; numbered rows can be voided/restored, not deleted. The paperclip opens accepted enclosures and private upload/download, retaining the row number. Work remains unposted through all of these actions.

Journal rows show posting ID first, followed by reference, files, debit account/amount, a separate VAT-included checkbox column, credit account/amount and VAT evidence. The entry row stays at the top and saved rows show newest posting IDs first. EP supplies the credit prefill: invoice total from the first VAT-configured account (debit before credit), or the debit amount without VAT configuration. Gross entry preserves the total; net entry adds configured ordinary VAT, while reverse charge/no-VAT follows rule invoice totals. Unavailable VAT leaves the calculated credit blank. Users may override credit or choose Use calculated amount; edits/cancel/retry preserve the original choice. These remain work drafts, with final VAT ledger legs and balancing in the later posting workflow.

The journal uses the available screen width. Its grid gives spare width to line reference; shrinking contracts reference first, accounts next, and amounts last, with internal scrolling below the usable minimum. Both VAT headings read VAT: the first row cell contains only an inclusion checkbox, and the second only the localized total (zero when no VAT is configured). Hover titles and accessible names retain basis/account explanations and VAT codes/errors; pending/error amounts show an ellipsis/dash rather than a false zero. Use account default remains among row actions. Other views keep their existing width.
