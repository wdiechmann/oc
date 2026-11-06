# UI and API

- `/session/new`: email form plus single-use sign-in token form. TOM requests delivery material from EP and sends a message through its configured provider; development messages are in TOM's own tmp/outbox.
- `/`: authenticated tenant creation and open-by-UUID forms. Retains the most recently opened UUID as a convenience.
- `/tenants/:id`: EP-authorized tenant name, readiness and projection version; explicit refresh for pending processing.
- Sign out: removes TOM's encrypted browser session. EP revocation is not yet implemented.
- `/up`: process liveness.

TOM server calls only these EP endpoints: POST `/api/v1/auth/magic-links`, POST `/api/v1/auth/magic-links/verify`, POST `/api/v1/tenants` with an Idempotency-Key, GET `/api/v1/tenants/:id` with Bearer authentication. Browser forms use Rails authenticity tokens. Bearer credentials are neither rendered nor sent directly by browser JavaScript.

The interface uses responsive Phlex components, semantic headings, explicit labels, keyboard focus states and Tailwind utilities. It requires no JavaScript runtime, external fonts or third-party browser services.


## Occasion screens

- `/tenants/:tenant_id`: now lists projected occasions and provides **Create occasion**.
- `/tenants/:tenant_id/occasions/new`: name, tenant-unique short name, expiry review date (UTC end of day) and optional self admin assignment.
- `/tenants/:tenant_id/occasions/:id`: name, lifecycle, recruitment state, review deadline and projection version; explicit refresh while pending.

Backend calls add POST/GET `/api/v1/tenants/:tenant_id/occasions` and GET `/api/v1/tenants/:tenant_id/occasions/:id`. Creating an occasion never opens recruitment. Expiry dates record a future review deadline; the expiry workflow is pending.


## Tenant-admin invitations

- The tenant overview links to `/tenants/:tenant_id/admin_invitations`: email invitation form, current lifecycle/expiry and pending **Revoke** actions. This shows up to 100 recent invitations.
- The signed-in header links to `/invitations`: the current verified email’s pending invitations with explicit **Accept tenant-admin invitation** forms. Acceptance redirects to the newly accessible tenant.
- TOM delivers invitation messages by SMTP or its private development mailbox. Invitation links open the TOM inbox and confer no authority.

Backend calls add GET/POST `/api/v1/tenants/:tenant_id/admin-invitations`, POST on its `/:id/accept` and `/:id/revoke` routes, and GET `/api/v1/me/tenant-admin-invitations`. All writes carry idempotency keys and use the browser user’s existing EP Bearer session. Role and actor scope remain EP-controlled.


## Occasion-admin invitations

Tenant admins see **Invite occasion admins** on the occasion overview. `/tenants/:tenant_id/occasions/:occasion_id/admin_invitations` names the occasion and offers invitation creation plus pending revocation. The shared **Invitations** page labels occasion versus tenant roles and provides explicit occasion acceptance. Accepted occasion cards show **Open occasion** while the current grant and lifecycle remain eligible. Occasion-only recipients return to their inbox rather than an inaccessible tenant overview.

EP calls use the nested occasion `admin-invitations` collection and its accept/revoke routes, plus GET `/api/v1/me/occasion-admin-invitations`. Recipient identity, scope, sponsor authority and grants remain EP-owned.


## Recruitment

- Occasion overview: **Manage recruitment**, available to current tenant/occasion admins according to EP.
- `/tenants/:tenant_id/occasions/:occasion_id/recruitment`: public campaign fields and manual-review policy confirmation when closed; shareable application-page link and close-with-reason form when open; up to 100 recent applications awaiting review. No admission action is exposed.
- `/recruitment/:tenant_id/:slug`: published intake instructions and notice, sign-in link or notice acknowledgment/submission form. Successful sign-in returns to this locally generated path.
- `/recruitment/received`: authenticated confirmation of the session's recorded application; explicitly states pending review and no membership/assignment.

EP integration adds scoped recruitment GET/open/close/applications endpoints and the public recruitment lookup. Application intake requires current policy version and verified identity. Public pages and forms use no-store responses; no database or business-state cache is added to TOM.


## Message-delivery boundary (agreed target)

The browser talks to TOM; TOM's backend requests an invitation or authentication challenge from EP, receives the necessary delivery material in the API response and sends the message. The recipient then verifies/accepts through the application using EP validation. EP does not send the user-facing message as part of the intended contract. This contract is now implemented: EP-side delivery workers/adapters are removed and the browser never receives the protected EP delivery response.


## Clickable sign-in and returning admins

`GET /session/verify?token=…` stages the magic-link token in TOM's encrypted HttpOnly session and redirects to `/session/confirm`; it does not redeem the token. The explicit confirmation POST calls EP using the backend credential. Sign-in from an invitation returns to the inbox for explicit acceptance; recruitment sign-in retains its application-page return path. A normal later sign-in returns home, where **Your administration** lists currently authorized tenants and occasions from EP `/api/v1/me/workspaces`.

All seven admin signup/send/accept/re-sign-in flows were browser-verified using TOM's own file delivery. Real SMTP provider connectivity requires operator configuration and has not been externally verified.

## Monitoring and in-context errors

Navigation now includes **Monitoring**, an EP-authorized tenant/occasion scope selector, filtered issue/observation lists with freshness and pagination, and issue details with timelines and acknowledge/assign/resolve/reopen actions. Explicit refreshes and actions update the existing monitoring region using Turbo Streams. Stopped views and access loss clear the protected region and show unavailable status.

Submitted-form errors update an accessible inline feedback region while preserving ordinary input. A correlation reference accompanies errors; uncertain receipted operations offer a signed completion-check link and up to three automatic GET checks. Accepted commands are never automatically resubmitted, and provider acceptance is never presented as delivery. See [monitoring.md](monitoring.md) for source configuration, user flows, fallbacks and current limitations. Real-API request verification passed; Playwright browser verification was unavailable in this session.

## Monitoring operations (local implementation)

Monitoring scope selection offers Platform monitoring only to an explicitly granted operator. Sources and alert rules provides scoped registration/revocation, threshold/window/cooldown setup, eligible recipient selection, enable/disable, maintenance suppression and recent delivery outcomes. Issue details offer named assignment and separately authorized diagnostics. Existing Turbo inline feedback remains in place; a separate worker performs alert delivery.

Development sign-in: submit the email form, then click the sign-in link in the flash notice. The link leads to the existing confirmation page; the flash disappears after one display. Default private file delivery remains available as before.

Monitoring opens on the scope list without the persistent reporting warning. Expand Reporting setup to inspect reporting-source availability and whether this instance recorded a successful alert-worker check within 30 seconds. Settings links use the existing authorized tenant/occasion flows.

Recruitment posters and application receipts have no TOM administration topbar/footer. Both signed-out and signed-in visitors see the required privacy acknowledgment. Signed-out visitors continue to sign-in, return to the poster and confirm the current notice when submitting; the sign-in step creates no application. Privacy link, checkbox and CTA occupy separate blocks on desktop and mobile.
