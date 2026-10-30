# Finance setup contract

All routes require a backend credential and a current operator session. Base:
`/api/v1/tenants/:tenant_id/finance/books/:book_id/setup`.

- `GET /`: current permissions, projected accounts/bindings, source/latest setup versions and ready/pending status. Tenant administrators may inspect setup and assign/revoke stewards; only an explicitly assigned steward may change accounts or bindings. No inheritance from parent books or occasion administration. No posting/payment authority is granted.
- `POST /stewards`: `{identity_id, active, expected_version}`. Tenant administrators explicitly assign/revoke the role. Initial UI candidates are existing active tenant/occasion administrators; the API accepts an existing active verified identity UUID. No identity is created.
- `POST /bindings`: `{occasion_id, active, expected_version}`. A steward binds/unbinds a current draft/active occasion in this tenant. Each occasion has at most one book; several occasions may share a book. An existing binding must be removed by that book's steward before reassignment. Unbinding does not rewrite occasion-owned records.
- `POST /accounts`: `{number, name, kind, expected_version}`. Kind is `posting`, `heading` or `total`; number is a case-sensitive string (1–40 letters/digits/dot/underscore/hyphen), unique and reserved within the book, including leading zeroes. Totals are labels only at this stage; no formula or posting semantics are activated.
- `PATCH /accounts/:account_id`: `{number, name, kind, active, expected_account_version, expected_version}`. Numbers remain reserved after renumbering/deactivation. Account ID is the initial AccountCreated event ID, independent of number. Changes require both current account and setup revisions.

Mutations require `Idempotency-Key` (1–128 safe characters), reject extra fields, and return command/book/tenant/event IDs, stream_version and replayed. Use `/api/v1/me/commands?command_type=FinanceSetup:<action>&idempotency_key=...` for private original-receipt reconciliation; actions are `steward`, `binding`, `account_create`, `account_revise`. Authority is checked before replay. Errors: 401 unauthenticated; 404 unavailable scope/access; 409 version_conflict, number_taken, binding_taken, idempotency_conflict; 422 invalid_setup; 503 view_stopped. A lost response never establishes rollback.

Protected current tables and per-book transaction locks govern acceptance and revocation. A tenant/occasion lock protects competing bindings. `finance_setup` events publish snapshots through outbox/inbox to a background MV; reads expose lag and refuse stopped controls. Grant candidates/current authority are live restricted control data, not financial authorization from the MV. The view can be rebuilt without appending events or dispatching financial work. Account ordering, formulas, imports, periods and journal permissions follow later slices.

Example account command: `{"number":"0010","name":"Bank","kind":"posting","expected_version":1}`.
