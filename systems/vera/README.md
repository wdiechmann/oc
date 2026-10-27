# VERA — Financial Control, Accounting and Settlement

VERA is a separate Rails client/backend for the finance domain in [system_2_plan.md](../../system_2_plan.md). It runs alongside TOM and talks to EP through HTTP APIs. It has no Active Record, local business database, Active Job, Action Cable, shared TOM sessions or direct PostgreSQL access.

## Run locally

Ruby 3.4.4 and Rails 8.1.4; all versions are pinned in Gemfile.lock. From this directory:

```sh
bin/setup --skip-server
bin/dev
```

Open **http://localhost:3001**. `bin/dev` runs Rails on loopback and Tailwind's watcher without Node/Foreman. `bin/rails server` also defaults to port 3001. `PORT` overrides the port and `EP_BASE_URL` overrides the fixed EP origin (default `http://localhost:4000`). `.env.example` documents configuration; Rails does not automatically load it.

`GET /up` checks VERA liveness. `GET /up/ep` performs a bounded readiness check against EP and returns 503 if unavailable, redirected or malformed. These endpoints do not imply that authentication or financial authority has been configured. The home page needs no EP connection.

## Sign in

Open **http://localhost:3001/session/new** and use the email of your existing identity managed through TOM. VERA requests a sign-in-only challenge from EP, delivers the VERA link, and stores its own encrypted-cookie session after explicit confirmation. It has no signup, invitation, recovery or identity-administration workflow. If the identity is unknown or throttled, the public response remains generic and no message is sent. A link opened by an email scanner does not redeem the challenge; the user must press Continue to VERA.

Development defaults to a private message file in **systems/vera/tmp/outbox**, not external email. Open its sign-in URL and confirm. SMTP delivery is configurable through the VERA-prefixed variables in .env.example. App URLs come from trusted configuration, not the incoming Host header. No bearer or magic-link secret is rendered into ordinary pages or event payloads.

After signing in, VERA asks EP for the user's currently authorized tenants/occasions. It does not create new permissions or treat tenant administration as financial posting authority. Book management is next. The signed-out home page and liveness check still work without EP. Failures in submitted forms appear inline through Turbo with safe input preserved.

Sign out revokes this EP session and clears VERA's cookie; it does not sign the user out of TOM. If revocation cannot be confirmed, VERA still clears its browser session and explicitly reports the uncertainty; the EP session retains its normal expiry. These apps do not share cookie encryption keys or runtime secret files.

## EP backend credential and restart

`bin/setup` provisions a **separate** local `vera` backend credential through `bin/provision-ep-backend`. This explicit operator setup writes private ignored files at `systems/vera/config/ep_backend_token` and `systems/ep/config/backend_api_tokens.json`, retaining other registered entries and refusing mismatched VERA credentials. Each running application reads only its own file. No user identities, grants or tenants are created by provisioning.

After this feature's initial install, apply EP migrations and **restart both EP and VERA** to load their new schema/configuration, backend registration, dependencies and cookie configuration. The current development migration and credential have already been prepared in this workspace. Later setup runs retain the credential.

`VERA_EP_BACKEND_TOKEN` overrides VERA's local credential. In production provision that secret (or EP_BACKEND_TOKEN as a production-only fallback) independently, and register the matching `vera` entry in EP_BACKEND_TOKENS_JSON through the secret manager. The extra JSON file in EP is development-only; environment entries take precedence. Do not reuse TOM's credential or change its registration. Production also needs explicit HTTPS VERA_PUBLIC_BASE_URL/TOM_BASE_URL, SMTP credentials and the normal Rails deployment secrets.

EP owns accepted business records, current authority and query MVs. VERA uses only its API; no local database is introduced. Full finance commands, a general application-capability registry and VERA monitoring ingestion remain subsequent work.

## Verification

```sh
bin/rails test
bundle exec rubocop --cache false
bin/rails zeitwerk:check
bundle exec brakeman --no-pager
```

Tests block real network connections and cover the landing page, database-free boot, dependency outage, malformed readiness responses, fixed-origin validation and redirect refusal. Tailwind is built as part of Rails tests. Browser verification uses Playwright.
