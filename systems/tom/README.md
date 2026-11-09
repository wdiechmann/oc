# TOM — Tenant & Occasion Management

Rails / Phlex / Tailwind UI with no database, Active Record, SQL client, background queue or independent business-data store. Browser → TOM backend → EP API. EP owns identity, permission and business state; TOM owns the email message, application URL, delivery provider and its delivery retries. No EP filesystem mailbox or delivery worker is used.

## Start

```sh
cd systems/tom
bundle install
bin/provision-ep-backend
bin/dev
```

Keep EP running on http://localhost:4000. TOM opens at http://localhost:3000. `bin/dev` runs Rails and the Tailwind watcher without Node or Foreman. `bin/setup` also provisions development backend credentials. Existing matching private credentials are retained; mismatches are not silently overwritten. The two running applications each read only their own gitignored mode-0600 configuration file. In production provide EP_BACKEND_TOKEN independently to both apps through their secret managers; EP_BACKEND_ID defaults to tom. The token is never sent to browsers.

`EP_BASE_URL` changes the EP origin; `PORT` changes TOM's port. Set `TOM_PUBLIC_BASE_URL` to TOM's externally reachable origin (HTTPS required in production); message links use this configured value, not the browser's Host header. `.env.example` is documentation, not automatically loaded.

## Delivery

Development defaults to `TOM_DELIVERY_METHOD=file`: TOM writes mode-0600 JSON messages under its private mode-0700 `tmp/outbox`. The development flash also shows the clickable sign-in link after a successful request. This is TOM's own development delivery provider, not a shared filesystem integration with EP. A magic link opens a confirmation page; clicking **Confirm sign-in** redeems it. GET/prefetch alone never creates a session. The existing manual token entry remains available, but normal testing now follows the clickable link.

For email set `TOM_DELIVERY_METHOD=smtp`, `TOM_MAIL_FROM`, `TOM_SMTP_HOST`, and optionally `TOM_SMTP_PORT` (587), `TOM_SMTP_USERNAME`, `TOM_SMTP_PASSWORD` and `TOM_SMTP_SSL=true` for implicit TLS (465). Otherwise STARTTLS is required. Configure actual provider credentials yourself; no production provider has been connected or externally tested. Production cannot fall back to file delivery. Tests force Mail's in-memory test provider and never send email externally.

Magic-link/invitation SMTP/file delivery is synchronous in TOM. Monitoring alerts separately use the EP intent/acknowledgment protocol and TOM worker described below. A failed invitation send retains its idempotency key. Retrying asks EP for the same still-live invitation and sends it again, with a stable Message-ID; this cannot guarantee exactly-once SMTP delivery. A failed/lost magic-link issuance requires an explicit new request, invalidating the previous challenge for this backend. TOM does not automatically retry issuance. Throttled responses remain generic to the browser and generate no message.

## Seven administration flows

1. Initial signup/sign-in: email → EP-issued challenge → TOM message → link confirmation → canonical EP identity/session → first tenant creation grants tenant_admin.
2. Tenant-admin invite: from tenant overview choose **Invite tenant admins**; TOM sends the material returned by EP.
3. Tenant invitation acceptance: open the message's invitation link, verify the invited email and explicitly accept in **Invitations**. Login alone grants nothing.
4. Later tenant-admin sign-in: a new message/session preserves identity/grants; the home page lists authorized tenants under **Your administration**.
5. Occasion-admin invite: a tenant admin opens the occasion and chooses **Invite occasion admins**; TOM sends a named, scope-specific message.
6. Occasion acceptance: the verified recipient explicitly accepts and receives only the named occasion grant, with no tenant grant or participant membership.
7. Later occasion-admin sign-in: the home page lists the currently authorized occasion, without tenant administration or sibling access.

Invitations last seven days and pending ones may be revoked. EP checks current sponsor authority, parent lifecycle and recipient email at acceptance. Accepted occasion cards also provide **Open occasion** links while their grants remain active. Session expiry/revocation and MV controls remain EP-authoritative.

## Occasion and recruitment setup

Create an occasion with name, tenant-unique short name and future expiry review date (end of date in UTC). Optional self occasion administration is explicit. It starts as draft with recruitment closed. The review date does not automatically schedule a WorkItem or erase data yet.

**Manage recruitment** lets current tenant/occasion admins publish a title, instructions, approved HTTPS notice link and fixed manual-review policy, then open or close intake. Share the application-page URL. Verified users acknowledge the policy and submit one expression of interest, pending review. Closure, expired review dates and changed policy block new intake independently of MV lag. Admins can see the scoped pending queue; no admission/membership/assignment action is implemented.

## Security and limits

Bearer sessions stay in Rails' encrypted HttpOnly SameSite cookie, not JavaScript, localStorage or URLs. Magic-link callback tokens are staged in that cookie and removed from the address bar before the confirmation POST. Rails filters token parameters, uses CSRF protection/no-store responses and forbids third-party scripts. Keep Rails secrets safe and shared across replicas. Local sign-out still clears only TOM's cookie; EP session-revocation integration remains future work.

Backend secrets, development message files and their backups need appropriate operational retention. Production application registry/scopes, source abuse controls, privacy/erasure and backup workflows, admin removal/recovery, workforce admission and load validation remain incomplete. A notice acknowledgment is not blanket consent or production compliance certification.

## Checks

```sh
PARALLEL_WORKERS=1 bin/rails test
bundle exec rubocop -a
bin/rails zeitwerk:check
node --test test/javascript/monitoring_test.mjs
bundle exec brakeman --no-pager
```

Tests stub EP HTTP, block external network and use Mail::TestMailer, with no PostgreSQL. See docs/architecture.md, docs/roadmap.md and docs/ui.md.

## Monitoring

TOM now captures safe errors/outcomes through EP and provides scoped monitoring lists,
issue timelines and versioned actions. Turbo keeps form errors/status feedback in place;
uncertain commands are checked rather than replayed. See [monitoring setup and behavior](docs/monitoring.md)
for EP source provisioning and `TOM_MONITORING_SOURCES_JSON`. Without a source, reporting
remains in local logs; existing EP monitoring records can still be queried. Run `bundle install`
and restart TOM to load the new dependency/configuration. Independent collectors, alerts,
retention automation and Playwright visual verification remain pending.

## Monitoring worker and collector

After migrating EP, use Monitoring → Sources and alert rules for scope administration. Run `bin/monitoring-worker` separately for alert delivery and supervise its `/up/monitoring` heartbeat. The development delivery sink sends no external mail. Run an [independent collector](../monitor/README.md) with TOM's private spool/key for outage recovery; see [monitoring UI/API behavior](docs/monitoring.md) and [pending deployment decisions](../../docs/pending_details.md).
