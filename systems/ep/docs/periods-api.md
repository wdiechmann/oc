# Book accounting periods (v1)

Base: `/api/v1/tenants/:tenant_id/finance/books/:book_id/periods`.
All endpoints require a registered backend and current operator session. Current tenant administrators may inspect setup metadata; explicit active book configuration stewards create/revise/open/close periods. Reopen additionally requires an explicitly assigned `can_reopen_periods` permission on that book's active stewardship, plus a nonblank reason. No parent inheritance, occasion-admin shortcut, journal or payment authority is introduced.

- `GET /`: book name/calendar/timezone/authority, current permissions, accepted/source registry revisions, ready/pending status and projected periods with complete transition history. Stopped views return 503 instead of stale success.
- `POST /`: `{name, start_date, end_date, expected_version}` creates a Draft. Dates are strict `YYYY-MM-DD`, inclusive, in the book's accounting calendar. Start must not follow end; periods in one book cannot overlap, including shared boundary days. Different books have independent periods.
- `PATCH /:period_id`: `{name, start_date, end_date, expected_version, expected_period_version}` revises a Draft only. Dates/name become immutable when first opened. No deletion or relabeling of closed history is allowed.
- `POST /:period_id/open`: `{expected_version, expected_period_version}` Draft → Open.
- `POST /:period_id/close`: `{expected_version, expected_period_version}` Open → Closed.
- `POST /:period_id/reopen`: `{expected_version, expected_period_version, reason}` Closed → Open. Reason is 1–500 trimmed characters and records who/which application reopened the period.

Mutations require `Idempotency-Key` (1–128 safe characters). Current authority is checked before replay; a changed payload under the same key conflicts. Success returns command/tenant/book/period/event IDs, accepted registry stream version and replayed. Reconcile lost responses through `/api/v1/me/commands?command_type=FinancePeriod:<action>&idempotency_key=...`, where action is create/revise/open/close/reopen. Checks never repeat a mutation. An explicit original-body/key retry remains idempotent.

Reopening permission is assigned/revoked by a current tenant administrator through `POST .../setup/reopening-authority` with `{identity_id, allow, expected_version}` and setup idempotency semantics (`FinanceSetup:reopening_authority`). The identity must already be an active steward for that book. Revoking stewardship also clears reopening permission; reassigning does not resurrect it. Setup GET exposes this restricted control attribute to tenant administrators.

Errors: 401 unauthenticated/backend required; 404 unavailable scope/access; 409 version_conflict, period_overlap, invalid_transition, idempotency_conflict; 422 invalid_period or invalid_reason; 503 view_stopped. Fields are allow-listed. Error responses and reads are no-store. Financial dates are never coerced through UTC; accepted/audit instants are UTC.

Protected period/state rows and a per-book registry stream enforce date/version/state guards. Mutations acquire the shared book setup-authority lock before the registry lock; revocation cannot race stale authority. Transitions/revisions lock the period row FOR UPDATE. Future posting handlers must validate book activation/accounting authority and their own financial authority, then call `Periods.lock_open!` inside the SAME acceptance transaction and retain its FOR SHARE row lock through event/ledger commit. Close takes the conflicting row lock, so posting/closure are ordered. This guard neither posts a journal nor confers financial authority.

`finance_periods` outbox/inbox projection and serving controls are independent of setup/CoA. Ordered replay/rebuild only recreates query rows/history; it cannot open an external ledger or execute finance. External-authority books use these as local preparation controls; no external period operation or external-posted assertion is implied. No journal API, balance check, year-end closing or historical report release is delivered in this slice.
