# TOM — Tenant & Occasion Management

## Delivery ownership

TOM's backend requests invitations and authentication challenges through EP's API (potentially MCP later), receives the invitation/challenge delivery material in the API response and sends the appropriate message to the intended recipient. EP owns lifecycle/verification and scoped authority; TOM owns message presentation, application URLs and delivery/provider handling. No separate acknowledgment/queue protocol is required for this handoff. See [the detailed contract](docs/architecture.md#application-contract-and-message-delivery).

**Implementation status:** This is the agreed contract. Current code still uses EP-side development mailboxes and an invitation delivery worker, and magic-link requests return only `check_your_email`. Moving delivery material into the protected backend API response and moving delivery/provider handling into TOM is pending implementation. Existing mailbox instructions below describe that temporary code, not the intended application integration.


A separate Rails 8.1 / Ruby 3.4.4 application with Phlex and Tailwind CSS. TOM has no database, SQL client, Active Record, background worker or independent business-data store. Its backend calls EP over HTTP; browsers talk only to TOM.

## Start locally

Keep EP running at http://localhost:4000, then in another terminal:

```sh
cd systems/tom
bundle install
bin/dev
```

Open http://localhost:3000. `bin/dev` runs Puma and the Tailwind watcher without Foreman or Node. For a different EP origin, export `EP_BASE_URL=http://localhost:4000`; for a different TOM port export `PORT=3001`. `.env.example` is documentation, not automatically loaded.

Request a sign-in message in TOM. EP currently writes development messages to its private `systems/ep/tmp/magic_links/` directory. Paste the **single-use magic-link token**, not an existing Bearer session token, into TOM's sign-in form. TOM exchanges it with EP. Real email delivery and clickable magic-link callbacks remain future integration work.

Create a tenant, or open an existing tenant using its UUID. EP checks your current access on every tenant read. The tenant overview lists occasions and offers creation. Tenant-admin invitations are available; tenant listing remains future work.

## Security and state

The EP Bearer token and its expiry are held in Rails' encrypted, authenticated, HttpOnly, SameSite=Lax session cookie. This cookie is browser-held encrypted state, not a server-side session database. Tokens never enter JavaScript, localStorage, URLs or rendered HTML. Production cookies require HTTPS. TOM checks expiry; EP remains responsible for current authorization and revocation. Protect `SECRET_KEY_BASE` and use the same secret across replicas.

Sign-out currently clears TOM's cookie; it does **not** revoke the EP session. A copied cookie remains usable until EP expiry/revocation. An EP revoke-session endpoint is required before production sign-out can promise server-side invalidation. No local token blacklist or identity database is introduced.

Forms use Rails CSRF protection; responses are `no-store`, credentials are filtered from Rails logs, and CSP disallows scripts and third-party resources. The fixed operator-configured EP origin prevents user-selected destinations; HTTPS is mandatory in production. The client has bounded timeouts and does not automatically retry requests. A session-held creation key survives uncertain outcomes for safe retries; EP owns authoritative deduplication. Local `/up` is TOM liveness, not EP readiness.

No cached tenant snapshot is served: pending projections can be refreshed, stopped projections fail closed, and foreign tenants remain unavailable. The last-opened tenant UUID is only a navigation hint in the encrypted session. Multiple tenants are supported through EP access checks, with no tenant scope inferred from client claims.

## Checks

```sh
PARALLEL_WORKERS=1 bin/rails test
bundle exec rubocop -a
bin/rails zeitwerk:check
bundle exec brakeman --no-pager
```

Tests stub EP HTTP, block external traffic, and need no PostgreSQL. See [architecture](docs/architecture.md), [roadmap](docs/roadmap.md) and [UI](docs/ui.md).

## Occasions

Apply EP's new migration, refresh your tenant overview and choose **Create occasion**. Enter a name, tenant-unique short name and expiry review date. TOM converts the end of that date in UTC to EP's timestamp. The checked “Assign me as occasion admin” option is explicit and may be cleared; it grants administration without participant membership. Recruitment remains closed.

The creation form and pending/ready detail screen use EP commands and materialized queries. The tenant overview lists projected occasions and can be refreshed. Duplicate short names and invalid fields retain form values; creation keys are tenant-bound and retained across uncertain responses. EP rechecks authority on the actual write even after a form was opened. Expiry review scheduling, retirement is not implemented by this form.

## Invite another tenant admin

From the tenant overview choose **Invite tenant admins**. Enter the prospect’s email. An invitation lasts seven days and can be revoked while pending. Creation records an invitation, not a grant and not a claim of email delivery. Development messages are written privately by EP under `tmp/admin_invitations`.

The prospect signs in using that same email, opens **Invitations** in the header, and explicitly accepts. EP checks their verified identity and the inviter’s current authority before granting tenant-wide admin access. Expired, revoked, wrong-recipient and inactive-sponsor invitations cannot grant access. The accepted recipient can then open the tenant. Revocation controls apply to pending invitations; removing an accepted administrator is a separate future workflow.

## Invite an occasion admin

A tenant admin opens the occasion and chooses **Invite occasion admins**. The form names the occasion, records a seven-day invitation and permits pending revocation. The prospect signs in with the invited email, opens **Invitations**, and chooses **Accept occasion-admin invitation**. They receive access only to that occasion and can return using its **Open occasion** card. The card is hidden when their current grant or parent lifecycle is no longer valid.

Occasion admins cannot use these invitations to grant tenant administration or appoint additional admins; that action remains with tenant admins. Invitation acceptance creates no participant membership. Notifications still use EP’s private development mailbox; no real email delivery has been added.

## Open recruitment

From an occasion choose **Manage recruitment**. Tenant admins and that occasion's admins can enter a public title, instructions and a published HTTPS recruitment privacy-notice URL, then confirm the manual-review/assignment policy and open intake. The resulting **Open application page** link is tenant-and-slug scoped and can be shared. Opening does not make the occasion active or accept participants automatically.

A prospect signs in from that page, returns to it after verification, acknowledges the notice and submits a minimal expression of interest. The application remains **pending review** and appears in the scoped admin queue. It creates no membership or assignment. The configured notice/policy version is checked again by EP on submission. Closing recruitment requires a reason and blocks new intake immediately, even before projection refresh. Reaching the occasion's review deadline also blocks new intake.

Applicant admission, vouching evidence, safeguarding/qualification checks, membership acceptance, applicant history/withdrawal, expiry-review tasks and notifications are subsequent work. Use an approved recruitment notice/purpose and complete the broader platform privacy/security/readiness work before production collection. No real email delivery was added.
