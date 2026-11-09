# Roadmap

1. Complete: standalone Rails/Phlex/Tailwind/Turbo client, database-free boot, EP readiness transport and initial tests.
2. Complete locally: VERA backend credential, existing-identity EP sign-in, private session/logout and current authorized tenant/occasion overview.
3. Complete locally: tenant draft books — EP create/list/detail/revise, guarded hierarchy, book MV, recovery and VERA book-management UI.
4. Complete locally: explicit book-scoped configuration stewards, occasion/book bindings and initial CoA list/create/revise/lifecycle editor, with current authority, projected setup, conflict comparison and receipt recovery.
5. Complete locally: dedicated paginated CoA line editor with canonical positions, type-specific VAT/category/formula fields, keyboard chart navigation and infinite scrolling.
6. Complete locally: book-scoped draft/open/closed periods, draft-only date corrections, separate reopening permission/reasons, protected posting-date guard, event history, query projection and receipt recovery.
7. Complete locally: book-scoped VAT/category label catalogues with explicit legacy adoption, stable IDs/versions, reserved mutable codes, lifecycle/history, current-reference validation and dynamic chart dropdowns.
8. Complete locally: reviewed chart CSV import/export — replacement by default with explicit merge, retirement/history and identity-preserving restore, bounded private uploads, scoped demo templates, optional reviewed creation of missing unique VAT/category codes, column mapping, whole-chart validation, before/after review, atomic version/digest-checked acceptance, complete-command projection and receipt recovery.
9. Complete locally: native reviewed row/block reordering and position rebalancing, full-chart membership validation, keyboard controls, atomic position-only acceptance and receipt recovery.
10. Complete locally: effective-dated VAT rates, deductible shares and signed reporting mappings with overlap/version guards, accepted rule history and exact calculation preview.
11. Complete locally: accepted chart formula rehearsal with explicit test balances, pinned reference breakdowns, exact nested arithmetic, row errors and revision-fenced read-only EP API.
12. Complete locally: reviewed versioned report definitions, stable signed account mappings, pinned line totals, history/coverage diagnostics and historical test-balance previews.
13. Complete locally: reviewed unposted journal drafts, exact debit/credit validation, effective VAT/period evidence, context fences, immutable correction history, projection recovery and private receipts.
14. Complete locally: work-in-progress paired line editor, Carla-style lookup, locale decimals, account-driven VAT, transactional per-book posting IDs and private enclosures.
15. Next: explicit financial posting authority and atomic posting guards, including VAT posting-account policy. Broader finance roles, financial controls, journals, settlement, consolidation and operational payments follow system_2_plan.md.

Regional CSV upload: separator detection and empty-row skipping happen in VERA’s bounded string parser; EP’s review and financial validation remain authoritative.

Reviewed import now accepts descriptive VAT/category values in independent catalogues, including Danish names and long VAT descriptions.

## Danish VAT preset drafts

Effective VAT rules offer 16 versioned Danish templates, including domestic VAT, qualifying restaurant/hotel deductions, EU/non-EU trade and domestic reverse charge. Selection fills an editable draft with source links and usage conditions; effective dates remain blank. Only a unique active alias match suggests a VAT entry, with UEUV distinct from UEUV2. Importing labels never accepts tax rules. Accepted rules and histories pin the source version and track customized values. Imported-goods assessment requires an explicit customs-statement VAT amount rather than calculating from supplier net. EP owns validation, calculation and provenance; VERA has no local policy database. See ../../ep/docs/danish-vat-presets.md.

Journal rows show posting ID first, followed by reference, files, debit account/amount, a separate VAT-included checkbox column, credit account/amount and VAT evidence. The entry row stays at the top and saved rows show newest posting IDs first. EP supplies the credit prefill: invoice total from the first VAT-configured account (debit before credit), or the debit amount without VAT configuration. Gross entry preserves the total; net entry adds configured ordinary VAT, while reverse charge/no-VAT follows rule invoice totals. Unavailable VAT leaves the calculated credit blank. Users may override credit or choose Use calculated amount; edits/cancel/retry preserve the original choice. These remain work drafts, with final VAT ledger legs and balancing in the later posting workflow.

The journal uses the available screen width. Its grid gives spare width to line reference; shrinking contracts reference first, accounts next, and amounts last, with internal scrolling below the usable minimum. Both VAT headings read VAT: the first row cell contains only an inclusion checkbox, and the second only the localized total (zero when no VAT is configured). Hover titles and accessible names retain basis/account explanations and VAT codes/errors; pending/error amounts show an ellipsis/dash rather than a false zero. Use account default remains among row actions. Other views keep their existing width.

Journal row actions live in a More context menu using the Carla vertical-dot SVG and shared focus-return conventions. A reusable VERA component/custom element uses a native top-layer popover so the horizontal grid cannot clip it. Save/Edit/Cancel/Void/Restore and account/credit reset actions keep the original row form, versions and command keys. Arrow keys/Home/End navigate, Escape returns focus without cancelling edits, outside clicks dismiss, and Enter in a row still saves. The action column is reduced to the icon width. No new dialog or business endpoint is needed.

Journal keyboard navigation: unmodified Home/End focus the first/last displayed row (including the new top row); Page Up/Down focus the previous/next row without wrapping. Preserve the same input column where available, scroll it into view, and retain unsaved edits. Up/Down keep native input caret behavior, including account search; lookup selection uses Enter or a result click. An open More menu retains its own arrow/Home/End navigation. Modified shortcuts and composition are untouched.

The journal ID heading reads ID; debit/credit amounts and both VAT columns, including headings, align right. Journal creation sends initial_row=true so EP atomically persists an empty numbered line. New line explicitly commits another empty row before editing; its ID and enclosure link are available immediately. The latest empty row opens for entry, and new rows prepend. There is no unnumbered placeholder and GET never allocates IDs. Attachment binding, edits and retries preserve that row’s ID; empty/voided rows remain in the audit register. Unsaved edits block creating another line.

Enclosure icons request a Phlex-rendered shared native dialog through Turbo Streams. Picker, review, binding and unknown-outcome completion/retry stay in the dialog; successful binding refreshes the journal’s enclosure count and current version fences. Closing/Escape restores focus to the original icon. Unsaved row edits remain in memory while enclosures are opened and attached; access loss clears dialog content. Enter in an editable row atomically saves it and creates the next numbered row while below the row cap, then focuses the first row reference. Menu Save remains save-only. Loading the journal focuses the first displayed row; dialog refreshes retain dialog focus. No GET allocates rows.

Account lookup now searches automatically once two trimmed characters are present, with no slash prefix. Matching is a case-insensitive literal substring anywhere in account number/name or VAT/category code/name; exact numbers rank first. Up/Down in an account query enters and traverses results, returning virtual focus to the input beyond either end; typing stays in the input and Enter commits the highlighted stable account ID. Escape closes; Up/Down can reopen. Other inputs keep native arrows, and Home/End/Page Up/Down keep row navigation. Debounce, cancellation and version/identity guards remain.

Credit prefill is the net amount after ordinary VAT is removed: gross 1,125 at configured 25% gives credit 900 and VAT 225. Net entry keeps its net base. Signed work entries are accepted using either ASCII minus or the rendered minus sign; negative draft values reverse debit/credit legs without negative leg values. VAT hover details show the intended incoming/outgoing counter-leg direction from the debit sign, separately from configured rule provenance. For −1,125 gross, credit is −900 and VAT −225, indicated as outgoing. Existing manual credit overrides and saved history remain intact; Edit refreshes automatic suggestions. Final tax-account posting remains later work.

Space on an enclosure icon opens its existing Turbo dialog. Leaving an account input resolves a unique exact account number and fills the canonical label/ID without moving focus; pending resolution is awaited before row submission. Ambiguous or partial matches remain unselected. Responses are guarded by input identity/value, cancellation and source cutoff; Cancel aborts pending lookup/submission. Escape from a row field or lookup returns to the row reference without discarding edits; Escape from More or an enclosure dialog also returns to that reference. Explicit More → Cancel still discards local edits.

Enclosures may be opened with unsaved row edits. Attachment refresh streams explicitly preserve local reference/account/amount/VAT overrides while applying fresh file counts and version fences. If the saved row or accounting context changed, preserve the older fences and surface a comparison message rather than silently rebasing edits. Pending projection responses keep the local row intact; ordinary access-loss streams still clear protected content. Cancel discards local fields against the freshly saved row without removing its attachments.

Effective VAT rules now map incoming VAT, outgoing VAT and non-deductible VAT to explicit book-local posting-account UUIDs. EP validates active posting-account scope, preserves mappings/history with source/rule fences and receipts, and rechecks dependencies for preview. The journal’s Saved posting preview shows gross/debit, net/credit and generated tax legs with exact totals, balance, account revisions and rule evidence. It handles gross/net, signed amounts, partial deduction, reverse charge and no-VAT rules; missing/invalid mappings, multiple VAT sources and incomplete/unbalanced rows stay explicit. Pristine new rows are excluded. Historical previews remain frozen. Preview completeness grants no posting authority and produces no ledger entries.

VAT setup is preset-first with a direct Danish preset selector. VAT-return box/component/sign controls and the separate non-deductible account override live under collapsed Advanced, with a readable preset/reporting summary. Blank non-deductible account means Follow expense/asset account; existing explicit overrides are preserved and shown. Non-deductible VAT folds into the business account in the saved preview and ordinary incoming-VAT credit suggestion. The VAT cell shows deductible input VAT (or outgoing VAT), with total/deductible/non-deductible amounts on hover. Example: 1125 including VAT at 50% deduction gives cost credit 1012.50 and deductible VAT 112.50. Zero deduction keeps the whole cost on the business account; reverse charge retains its invoice base while adding non-deductible VAT to the business cost.

Completed: code-centered VAT settings, date-specific coverage, grouped scheduled/history records and same-code change drafts. Scheduling remains explicit: end the previous period before saving a non-overlapping next period.

Completed: compact VAT index and shared detail dialog, including same-code scheduling, presets, revision/source references, streamed save/error recovery and index refresh after acceptance.

Completed: development sign-in links in the flash notice; existing confirmation and production delivery preserved.

Completed: VAT row-only Turbo updates after projection catch-up, with automatic read-only refresh and safe cancellation on navigation.

Completed: side-aware VAT amount suggestions and posting previews for income, expenses and reversals; optional minus normalization; VAT-direction preservation and correct cost-side non-deductible VAT.

Completed: explicit apply-VAT flag, net result-account amounts independent of legacy account inclusion defaults, VAT-off overrides and read-only VAT operation dialog.

Completed: dated VAT rule picker and source-side selection in the VAT operation dialog, Turbo draft-row recalculation and persisted per-row VAT overrides.

Completed: separate journal index, creation page and full-width journal detail with postings, saved preview and revision history.

Completed: journal header actions menu, shared history/delete dialogs and governed audited journal deletion with retained posting IDs.

Completed: journal details editing from the header menu through a shared dialog, replacing the inline expander.

Completed: saved posting preview as a journal header action and shared read-only dialog, replacing the inline expander.

Completed: journal User manual dialog from the header menu, containing the relocated editor instructions.

Completed: centered Journals index header menu for refresh and new-journal navigation.

Completed: New line moved to the first journal header menu position.

Completed: shared top-left toast stack for flash, streamed feedback, page messages and live journal notifications.

Completed: chart title context menu consolidates refresh, current/retired navigation, related configuration, reports, ordering and CSV actions while retaining direct search and line editing.

2026-11-06: The Journals index places its Chart of accounts navigation link in the header context menu; the standalone back link is removed.

2026-11-06: Journal validation and saved revision/status information occupy a fixed-height, scrollable header panel immediately left of the context menu. Configuration-stale and pending notices share this reserved space so changing feedback does not shift the posting grid on Enter. Floating flashes/toasts and the full saved posting preview dialog retain their existing behavior.

Completed: per-journal row menus, existing audited delete flow, account impact posting dialog and atomic EP-authoritative posting. Post is the explicit authorization/verification confirmation. Posted journals remain readable; external-authority posting/export and adjustment/reversal UI remain future work.

2026-11-06: Posting ignores untouched empty entry rows while retaining their numbered audit records. Entered references, accounts, amounts or attachments still require validation. Posting dialog row issues show the posting ID and avoid duplicate generic messages.

2026-11-06: The Post journal account-impact table ends with a Total footer summing the displayed accounts’ Prepost, Post and Postpost columns using exact minor units and the current decimal separator.

Completed: setup section actions open shared dialogs for steward assignment, permission to reopen periods and occasion links; inline assignment forms removed.

2026-11-06: The book detail title has a right-aligned, vertically centered context menu for Edit name and hierarchy, Back to books, Roles and occasions, Chart of accounts, Accounting periods, VAT and categories, and Refresh book. Editing opens the existing BookForm in the shared dialog; pending views/saves block opening it, and existing version/key, save, conflict and completion handling remain intact. Standalone navigation/actions and the inline editor are removed.

2026-11-06: Book configuration has a shared context menu aligned to the right and vertically centered beside its title. Open chart of accounts, VAT and categories, and Accounting periods move into this menu; their standalone links are removed.

2026-11-06: Accounting books has a title context menu containing Create book, Refresh books and Your workspaces. Each book card has its own menu beside the book name linking directly to its Chart of accounts and Journals, scoped by tenant and book ID. Hierarchy and book detail links remain visible.

2026-11-06: Each book’s index context menu includes Setup, linking to that book’s setup view with the current tenant/book scope.

2026-11-06: The Book configuration header menu includes Back to books, returning to the current tenant’s books index.

2026-11-06: The chart header menu includes Back to books, linking to the current tenant’s books index in both current and retired chart views.

2026-11-06: The Journals index header menu includes Back to books, returning to the current tenant’s books index.

2026-11-06: Disabled context-menu items are visibly muted, use the unavailable cursor and do not show an active hover highlight. Posted journal rows retain native disabled Post journal and Delete journal buttons, which keyboard navigation skips.

Completed: PDF/image enclosure previews in attachment review and saved document panels. Existing confirmation, download and unknown-outcome recovery remain available.

Completed: portable local PDF-text extraction and image/scanned-PDF OCR in enclosure preview, with read-only labelled suggestions and source text. Added a production Linux image with Danish/English Tesseract, Poppler, nonroot runtime and Linux gem platforms. Applying verified suggestions to a journal remains a later explicit action.

2026-11-06: Enclosure preview spans the full width above suggested document values. A bounded single-column grid allocates vertical space in a 3:1 preview/values ratio; suggestions scroll within their own panel, including while scanning. The layout applies to staged and saved documents on desktop and mobile.

Completed: labelled Tenant/Occasion workspace columns and direct linked-book navigation. Current book stewards can read their book detail without tenant-wide list/edit authority.
