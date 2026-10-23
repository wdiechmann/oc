# UI and API

- `/session/new`: email form plus single-use sign-in token form. Development instructions point to EP's private mailbox; TOM never reads that directory.
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
- Notifications currently use EP’s private development mailbox; no real email or credential-bearing invitation URL is generated.

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

The browser talks to TOM; TOM's backend requests an invitation or authentication challenge from EP, receives the necessary delivery material in the API response and sends the message. The recipient then verifies/accepts through the application using EP validation. EP does not send the user-facing message as part of the intended contract. Current private-EP-mailbox instructions describe temporary implementation awaiting this API/delivery refactor; no UI or runtime behavior changed in this documentation update.
