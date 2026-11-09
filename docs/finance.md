# Finance

## Dashboards

### Finans

én widget er finans balancer, hvor aktiver/passiver/egenkapital/lang og kort fremmedkapital/beholdninger vises i pie diagram

### Kassekladder

én widget er aktive kassekladder, hvor det ses hvormange linjer, i hvormange kladder, der er hhv registreret, godkendt, posteret, fejlbehæftede, mm

### Åbne poster

én widget er åbne poster, hvor antallet af hhv åbne debitor og kreditor åbne poster vises, hvorlænge den ældste fordring er overskredet, overskredne fordringer i debet og kredit, i beløb, mm

## Sub systems

An **accounting book** is the context for a set of accounting records: its chart of accounts, journals, postings, accounting periods, rules and balances. A tenant may maintain several books—for example, one for each occasion and a parent book for consolidated reporting. An occasion references its applicable book; neither a tenant, an occasion nor a book automatically represents a separate legal entity.

Books can be nested through `parent_book_id`. A parent is the same kind of book as its children: the hierarchy nests context, using the **same tables, associations, commands and event protocol** at every level. It does not introduce separate accounting subsystems or duplicate table sets. Each finance record retains its owning `tenant_id` and `book_id`, plus `occasion_id` where applicable. Parent/child links stay within the tenant and must not form cycles.

For example:

```text
Spejdernes Lejr (tenant)
└── Consolidated book
    ├── SL2026 book
    └── SL2030 book
```

A parent consolidates selected child books through account/report mappings and background-maintained MVs. Each posting belongs to exactly one book and remains there; consolidation preserves its source rather than creating another ordinary posting of the same amount. Parent books can hold their own authorized postings, including consolidation adjustments and eliminations, using the same posting model. Reports distinguish those adjustments from underlying child-book activity and prevent counting a source posting again through an intermediate parent.

Consolidated reports identify the included books, periods, mappings and accepted source cutoffs. They align currencies and reporting periods explicitly where these differ, and retain drill-down to the original postings. Consolidation does not silently alter a child's chart, balances or posted history. Nesting alone grants no additional access: viewing child detail, producing a consolidated result and posting parent-level adjustments each require the applicable authority.

The subsystems below operate within a selected book context; the same functionality applies at any level of the hierarchy.

- **Daily bookkeeping (løbende bogføring):** Enter or import transactions, attach supporting documents, assign accounts, VAT codes and cost centers, then validate and post journal entries.
- **Chart of accounts management (kontoplan):** Create and maintain account numbers, names, categories, posting rules and reporting mappings; deactivate obsolete accounts while preserving history.
- **Budgeting and forecasting:** Plan income, costs, cash flow and funding by tenant, occasion, cost center and work package.
- **Financial approvals:** Authorize spending, commitments, payments and adjustments within delegated limits.
- **Purchasing commitments:** Track approved orders, contracts and expected liabilities.
- **Open-item management:** Covers matching payments and credits against invoices, including partial payments, differences and settlement. It can also apply to clearing accounts beyond debtors and creditors.
- **Accounts payable:** Handle supplier invoices, reimbursements, allowances and contractor settlements.
- **Accounts receivable:** Invoice participants, sponsors and customers; track outstanding payments.
- **Camp payments:** Manage accounts, top-ups, purchases, balances, limits and wristband replacement.
- **Adjustments:** Process credits, refunds, transfers, write-offs and loss/damage charges.
- **Reconciliation and settlement:** Reconcile bank, cash, camp-payment ledger and external accounting records.
- **Cost allocation and reporting:** Compare budgets, commitments and actuals; report revenue, stock losses and financial exposure.
- **Accounting integration and audit:** Maintain authoritative accounting references and trace each financial action to its source and approval.

### Chart of accounts management (kontoplan)

The Chart of Accounts (CoA) is presented through a materialized view (MV), maintained in near real time by background jobs consuming accepted account changes. An accepted change schedules projection work immediately; the UI must still distinguish acceptance from completion of the MV update. The authoritative history remains in `event` and `event_details`, with synchronous account state protecting uniqueness, versions and posting eligibility as described in Persistence below.

Each CoA belongs to a tenant and an accounting book (`tenant_id`, `book_id`), and can be reused by several occasions within that book. An occasion is a reporting context, not automatically a separate CoA. Each account has a stable `account_id`: under the proposed convention, this is the ID of its original `AccountCreated` event. Subsequent revision events have their own IDs and never replace that account reference. Account numbers, names and display positions can change without breaking journal lines, tags, rules or report mappings.

#### Functionality

1. **Create and revise accounts.** Maintain account number, name, row type, display position and active/inactive status. Treat account numbers as strings so leading zeroes survive editing and CSV round trips. Account numbers are unique within a book; prevent reuse of a retired number for a different account. Distinguish posting accounts from headings and calculated totals/formulas; headings and totals never accept postings.
2. **Arrange the chart.** Use an integer `position` independent of account number. Moving a row changes its display order, not its identity or accounting meaning. Allocate gaps between positions; when renumbering is necessary, accept the affected ordering changes together. Concurrent moves validate the current ordering version rather than silently overwriting each other. Only the chart's canonical position order can be rearranged; temporary sorts and filters do not rewrite it.
3. **Classify and tag.** Associate accounts with categories and multiple tags through their stable IDs. Categories describe accounting/reporting classification; tags provide additional dimensions for filtering and grouping, such as function, funding source or programme. Changing an account tag does not retroactively change dimensions already recorded on posted entries. Account tags supplement the transaction dimensions used for occasion, cost center and work package; they do not replace them.
4. **Manage posting rules.** Associate versioned rules for posting eligibility, permitted debit/credit use, tax/VAT defaults and required or permitted dimensions. Clearly distinguish a suggested default from a mandatory rule. Check current effective rules when accepting journal changes and again when posting; a stale CoA MV cannot authorize a posting.
5. **Maintain reporting mappings and totals.** Map accounts to report definitions and report lines, and define totals using explicit account/group references. Validate references, scope and formula cycles. Changing display position must not change a formula's membership implicitly. Keep report definitions and mappings separate from the basic account row, and retain the configuration version used by a report or posting.
6. **Control lifecycle and effective dates.** Deactivate and, with authority, reactivate accounts. Deactivated accounts remain visible in history and historical reports, but cannot receive new postings outside their permitted effective period. Show affected draft journal lines and mappings before deactivation; require their resolution before posting. Changes do not modify already posted entries. Correct a mistaken account assignment through the journal adjustment/reversal workflow.
7. **Import CSV.** Offer a downloadable template and column mapping for account number, name, row type, position, status and supported classifications. Preview creates, revisions and unchanged rows; flag duplicates, invalid values, foreign references and conflicts before acceptance. Match existing rows by stable account ID where supplied, otherwise by book/account number. Never infer deletions from missing rows. Accept a validated import as an atomic, idempotent batch; an invalid or conflicting batch makes no partial changes. Importing balances or posting journal entries is a separate workflow.
8. **Export CSV.** Export the authorized book/chart or the explicitly selected filtered subset, showing which is being exported. Include stable account IDs and a documented schema/version so files can be matched safely on reimport. Resolve pending local changes before export and identify the accepted source version/cutoff represented by the file. Exporting a chart does not export the general ledger or balances unless separately requested.
9. **Apply bulk changes.** Allow selected accounts to receive or lose a tag, change category or be deactivated through an explicit preview and confirmation. Validate every affected account's current version and scope; accept the batch together or return the conflicting rows. One bulk command can emit several account/association events under one command reference.
10. **Preserve governance and integration.** Separate viewing, account maintenance, rule/report configuration and import/bulk-change permissions. Every accepted change records actor/application, scope, command reference, expected version and effective date where relevant. Integrated systems use the same commands, permissions and validation as the UI. If an external accounting system owns the chart, show its ownership and synchronization state, and route changes through that integration rather than allow competing edits.
11. **Inspect history and usage.** Show accepted revisions, effective dates and who or which application changed the account. Link to authorized journal usage, posting-rule versions and report mappings. Offer journal/balance drill-down as a separate view with its own reporting cutoff; do not make balances editable CoA fields.

The basic CoA MV contains account identity, scope, number, name, row type, position, status and source version. Tags/taggings, categories and posting rules have their own MVs, joined through stable IDs when displaying account details. Report definitions and mappings use the supporting tables `reports` and `report_definitions`, with explicit account/report-line associations. Their accepted configuration changes are also event-backed; these supporting tables are not a second independently editable source of truth.

#### UI

The CoA is edited like a line editor - submitting a line sends the event( & details) and updates the MV - and updates are streamed to the view whether due to user actions or other users updating the CoA or integrated systems with side-effects on the CoA.

Enter to edit a line - submit and update optimistically - if update fails, show 'new' line below the user's own line in editor mode
with an indication of who did the update.

CoA holds basic information only.

- tags/taggings, categories, posting rules are MV's
- report mappings are support tables, reports and report_definitions

### Kassekladde

#### Functionality

[oversæt til engelsk ved lejlighed]
Kassekladden er et eksempel på en applikation som er koblet på EP. I kassekladden gemmes udkast til finansielle transaktioner. Hver linje i kassekladden er i princippet en registrering af en hændelse, som har fundet sted. Mange hændelser vil være registreret automatisk, af agenter fra salg, indkøb, produktion, lager, og andre funktioner. For større overblik kan det vælges at lade hvert delsystem arbejde/registrere egne transaktioner i særskilte kassekladder.

#### UI

- linjer tilføjes automatisk  (opsætning: over/under) seneste
- en (opsætning: header/footer) viser beholdninger (opsætning: hvilke)
- dato foreslår (opsætning: dd/fast/seneste) dato
- tekst foreslår OCR genkendt bilags tekst
- bilagsnr foreslår (opsætning: næste ledige) nummer
- debet kontonr foreslår OCR genkendt debet konto nr
- debet kolonne beløb foreslår OCR genkendt debet beløb
- kredit kolonne kontonr foreslår OCR genkendt kredit kontonr
- kredit kolonne beløb foreslår OCR genkendt kredit beløb
- VAT foreslår VAT beløb
- afgifter mm foreslår afgifter løb

### Åbne poster

#### Functionality

Listen over åbne poster viser debitor/kreditor, beløbets størrelse, hvor længe fordringen/posten har været åben (fakturadato), hvornår den er forfalden (fakturadato + betalingstermin), status (modtaget/sendt|godkendt/afvist|anvist til betaling/lovet betalt|lukket)

#### UI

brugeren kan annotere en post, sætte den til betaling, godkende den (overstyre godkendelsesflow), afvise den

listens kontekstmenu kan konsolidere med bank, konsolidere med kontoudtog (tekst,CSV,PDF)

## Persistence

### Design position

Use the EP as the authoritative history of accepted finance changes, background-maintained MVs as the normal query path, and a small set of synchronously maintained supporting tables to protect posting and settlement invariants. Do not introduce a second independently editable ledger beside the EP. Supporting state for event-sourced finance is derived from events but updated atomically with their acceptance; it is not a lagging query MV.

This follows [suggested-data-store.md](suggested-data-store.md), [system_1_plan.md](system_1_plan.md) and [gdpr.md](gdpr.md). Proposed table names below describe responsibilities, not a requirement for a separate table for every concept.

### Scope and accounting authority

Distinguish the accounting book from the occasion. A tenant can have one or more `book_id` values representing explicitly defined accounting entities/books; an occasion references its applicable book and remains an operational reporting dimension. Do not assume that a software tenant or occasion automatically equals a legal accounting entity. The tenant's chart of accounts can be reused across occasions within the same book.

All finance records carry `tenant_id` and `book_id`; occasion-specific records also carry `occasion_id`. Tenant-level setup and genuine shared costs have explicit tenant/book scope. Cross-occasion allocations within a book are explicit dimension allocations; cross-book transfers need separately balanced entries in each book and a linked workflow. Validate every parent/reference scope.

For each book, designate exactly one authority for posted accounting: this EP-backed finance module or an external accounting system. With an external authority, local journal approval means ready for export, not posted externally. Record requested, accepted, rejected and reconciled states with external posting references. Do not let both systems independently edit the same authoritative posting.

### Persistence split

| Area | Accepted facts persisted in the EP | Supporting state or artifacts | Background query MVs |
|---|---|---|---|
| Chart of accounts (kontoplan) | `AccountCreated`, `AccountRevised`, `AccountDeactivated`; versioned tax-code and reporting/total-formula changes | `account_state` and setup state: stable account ID, unique book/account number, posting eligibility, effective version and applicable rules | Account list, reporting hierarchy, total/formula results and account balances |
| Journal batches and drafts (kassekladder) | `JournalCreated`, `JournalLineAdded`, `JournalLineRevised`, `JournalLineRemoved`, `JournalSubmitted` | Current versioned journal/line state for concurrency and posting eligibility; artifact references for receipts and OCR output | Editable journal list, current lines, error indicators, counts by status and balance previews |
| Approval and overrides | `JournalApproved`, `JournalRejected`, `ApprovalOverridden` with reason, actor and approved content version | Current approval/policy state and revision; changed material draft content invalidates its approval | Review queue, approval history and exceptions |
| Posted accounting | `JournalPosted` containing or referencing the complete immutable posting set; `PostingReversed` and replacement posting where needed | Synchronous `posting_guard`/posting index and protected numbering state; optional typed ledger-entry tables derived atomically from accepted events | General ledger, trial balance, balance sheet, income/expense views and dimension totals |
| Open items (åbne poster) | `OpenItemEstablished`, `PaymentRecorded`, `SettlementAllocated`, `SettlementAllocationReversed`, `CreditApplied`, `WriteOffPosted` | `open_item_state` and `settlement_allocation`: current original/residual amounts and versioned allocations needed to prevent over-settlement | Receivables/payables lists, aging, overdue totals, unapplied payments and reconciliation suggestions |
| Annotation and payment preparation | `OpenItemAnnotated`, `PaymentProposed`, `PaymentApproved`, `PaymentInstructionSubmitted`, `PaymentExecutionConfirmed` or `PaymentExecutionFailed` | Restricted note artifacts; durable payment-operation state, external request key and execution evidence | Payment queue, annotated open-item list and execution/reconciliation status |
| Budgets and obligations | `BudgetVersionCreated`, `BudgetApproved`, `CommitmentAccepted`, `CommitmentReleased`, `CostAllocated` | Versioned policy/commitment state where spending limits are enforced; no extra source of truth for totals | Budget versus actual/committed, forecast, funding and exposure views |
| Imports, bank matching and external accounting | `FinanceImportAccepted`, `ReconciliationMatchAccepted`, `ExternalPostingConfirmed`, conflict/rejection outcomes | Import/source deduplication keys, external mappings, integration operation state and controlled source files | Import exceptions, bank/statement matching suggestions, external drift and reconciliation views |
| UI preferences | `JournalPreferencesChanged` when accepted user configuration needs persistence/audit | Optional preference state using the same accepted configuration; unsaved local input need not emit events | Per-user/occasion journal defaults, sort direction, header/footer and displayed balances |

Inline editing is a UI behavior, not direct mutation of a query MV. The UI submits a command with an expected version; acceptance emits an event and updates protected state. Unsubmitted keystrokes can remain local. Persist explicit saves or bounded autosave revisions rather than an event for every keypress.

### Minimum supporting persistence

Reuse the core EP's `stream_head`, command receipts, outbox/inbox, scope controls and worker checkpoints. Add only responsibilities that cannot safely depend on asynchronous query state:

- **Book/account/period state:** Current book configuration, account eligibility, period status, and versioned VAT/tax/rounding rules required by acceptance. Chart rows used for commands are updated atomically with account-change events.
- **Journal and posting guards:** Current journal revision/status, approved revision, unique posting ID, posting source keys and number allocation. A journal cannot post twice, including under retries or concurrent requests.
- **Settlement state:** Residual amounts and allocation links protected across every affected invoice, payment and credit. Partial settlement is many-to-many; a user-facing “closed” flag is insufficient.
- **External-operation state:** Stable request/result IDs, desired/applied state and reconciliation evidence for accounting export, bank payment and imports. A successful HTTP submission is not evidence of settlement.
- **Artifact references:** Access-controlled, versioned receipts, invoices, statements, images and OCR suggestions in the document/object store; store IDs and integrity references in events instead of embedding binaries repeatedly.

These responsibilities can share tables or typed stream-state documents initially. The application must document how each event-sourced supporting record is rebuilt and verified. Never allow manual changes to derived state to create finance facts absent from the EP.

Typed `ledger_entry` tables are useful if downstream queries, constraints or export formats justify them, but they are not inherently required to make the EP a ledger. If introduced, give every entry a posting/event reference and update it in the posting transaction; it remains a constrained representation of the same accepted facts. A separate authoritative external ledger is the explicitly different integration mode described above.

### Posting transaction

A journal line describes a proposed accounting interpretation, even when an underlying sale or delivery already occurred. `SaleRecorded`, `JournalLineAdded`, `JournalApproved` and `JournalPosted` therefore have different meanings. OCR and subsystem agents propose draft values; they do not silently approve or post them.

1. Accept `PostJournal` with tenant/book scope, journal ID, expected revision, command idempotency key and acting identity/delegation.
2. Validate current authority, approved content revision, open accounting period, eligible accounts and tax-rule versions. Protect these checks against concurrent account deactivation, period closure and approval changes.
3. Validate the complete entry set: at least the required debit/credit legs, exact balance in book currency, valid transaction currencies/rates, explicit rounding and applicable dimensions. Use fixed precision decimals or currency-aware integer units, not binary floating-point arithmetic for money. A financial transaction may have many lines, not only one debit and one credit account.
4. Protect journal/posting uniqueness and allocate the required posting/document references under the adopted numbering policy. Record source date, posting date, server acceptance time and effective configuration versions separately.
5. Commit `JournalPosted`, all associated entry facts, journal/posting state, affected subledger state and publication intent atomically. Consumers must not see half of a posting set as a valid consolidated balance.
6. Return the accepted posting reference/version. Background jobs update journal, account-balance and open-item MVs. Display the committed result or a pending-view status until the relevant MV catches up.

A rejected posting produces no success event and no partial ledger entries. Later corrections use explicit reversal/adjustment entries with reasons and references; they do not edit posted amounts in place. Posting one batch need not hold every journal in the system behind one global stream.

### Open-item settlement and bank consolidation

Use distinct open-item IDs, payment IDs and allocation IDs. Example: an invoice for 1,000 receives allocations of 600 and 400 from two payments. The accepted allocation events explain how the item closed; the MVs show the resulting residual and status.

`AllocateSettlement` checks current residuals, currency/rate treatment, matching party/book scope and allocation policy, then atomically updates all affected guarded items and emits the allocation facts. Two concurrent allocations cannot consume the same remaining 400 twice. Reopening or correcting a match reverses its allocation explicitly; any resulting ledger effect must be included or linked through an explicit accounting workflow. Matching an already posted bank payment to an invoice must not post that payment again.

Bank/statement matching jobs read MVs and controlled imported files to suggest matches. Accepting a suggestion is a command with authoritative validation, not an automatic consequence of similar text or amounts. Preserve partial payments, unapplied payments, credits, differences and disputed balances. Sending a payment instruction does not close an invoice until the accepted payment/settlement evidence warrants it.

Avoid one overloaded status field: receipt/sending, approval/rejection, payment instruction/promise, dispute and settlement are separate dimensions. Notes do not change amounts; approval overrides require specific authority and a recorded reason, not merely access to a context menu.

### Chart of accounts and configuration history

Identify an account with a stable ID, not only its editable account number. Persist approved account, VAT/tax and reporting changes as versioned facts with effective dates. Posted entries retain the configuration versions and monetary tax results used at acceptance. Editing a label, rate or total formula must not silently change what an old posting meant.

Separate posting accounts from headings, totals and formulas (tælleværker). Only posting accounts accept ledger entries. Validate total/reporting formula references and cycles; compute their results in MVs. Deactivate used accounts instead of removing their history. Validate book/account-number uniqueness and period-close races in synchronous state.

### Query and job design

Suggested incremental MVs are `chart_of_accounts`, `journal_current`, `journal_status_counts`, `ledger_by_account_period`, `financial_statement_balances`, `open_items_current`, `open_item_aging`, `payment_queue`, `bank_match_candidates` and `budget_actual_commitment`.

Tenant admins bind each MV to its queue/job under the established control model. Workers update only affected accounts, periods, items and reporting groups, with source checkpoints and projection versions. Aging needs scheduled date-driven updates even when no new event arrives; retain due dates and calculation timezone/date. Stopping an MV or revoking its token blocks serving as defined in the core plan, while required cleanup still executes.

Dashboard amounts and balance previews come from these MVs. Posting, paying and allocating always revalidate protected state. Reports that must reconcile across several views use a common accepted source cutoff; do not present mismatched checkpoints as one balanced statement. A stale or failed job shows lag/error rather than a false zero balance.

### External systems, privacy and replay

Adapters deduplicate by source/application/book/object/version and distinguish local draft, export request, external acceptance and final reconciliation. External callbacks are reported outcomes that the owning handler validates. Replaying events rebuilds query/state representations; it must never resubmit bank payments, recreate invoices or export postings as new external transactions.

Keep identity references and receipt/contact details separate where practical. Apply [gdpr.md](gdpr.md) to narratives, artifact copies, snapshots, MVs, external mappings and backups. Identity erasure must not blindly destroy independently required accounting evidence; assess and restrict that retained subset rather than promising complete historic personal reconstruction. Record retention decisions separately from the routine occasion-retirement policy.

### Recommended first slice and verification

Start with one tenant/book, a versioned chart/period setup, one journal accepting multi-line balanced postings, partial open-item settlement and their incremental MVs. Reuse the shared EP infrastructure; add source agents and external accounting/bank adapters after these semantics are proven.

Verify duplicate posting retries, simultaneous posting/period closure, draft changes after approval, concurrent over-allocation, reversal without duplicate cash movement, deterministic configuration-aware replay, atomic publication of posting sets, and rebuilds without external side effects. Compare MV balances and open-item residuals against accepted facts at a common checkpoint. Add privacy-cleared references and cross-occasion/book isolation to the tests.

The supporting-state recommendation addresses concurrency as well as query speed: PostgreSQL's [transaction isolation documentation](https://www.postgresql.org/docs/current/transaction-iso.html) explains why read snapshots alone do not prevent every concurrent anomaly. The separation of accepted history, query projections and replay follows the [event-sourcing pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing); the finance-specific split above is a proposal for this solution.
