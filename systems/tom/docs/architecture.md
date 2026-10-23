# Architecture

## Application contract and message delivery

The application backend integrates with EP through its API; a future MCP interface may expose the same governed operations. EP creates and validates invitations/authentication challenges and returns the result, including the delivery material the authorized calling backend needs, in that request's API response. For example, TOM requests an invitation or magic-link challenge, receives it and delivers it to the intended recipient through TOM's email/SMS/provider integration. No shared database, filesystem mailbox or EP-specific delivery worker is part of this contract.

EP owns authority checks, tenant/occasion/recipient binding, expiry, revocation, verification/redemption, idempotency and accepted facts. The application backend owns message templates, application URLs, provider credentials, sending and provider retries. The API response is the handoff: recording an invitation/challenge does not mean that a message was delivered. Delivery acknowledgments, delivery queues or a separate notification service are not prerequisites for this request/response flow; any later delivery-status reporting must be an explicit optional API capability.

Delivery material is returned only to the appropriately authorized backend. A magic-link secret is sensitive authentication material: retain only its hash/verification state in EP and keep the raw value out of ordinary events, MVs, logs and unrelated clients. An invitation ID alone remains insufficient for acceptance; the verified intended recipient and current scope/authority rules still apply. Retries/reissuance must have documented API semantics so an uncertain response cannot silently create duplicate invitations or invalidate a challenge being delivered. This boundary preserves the existing recipient verification, rate limits and anti-enumeration requirements; it does not authorize a public browser endpoint to retrieve arbitrary login secrets.

**Implementation status:** Implemented. EP returns delivery material through protected API responses; TOM constructs and delivers the messages. EP delivery workers/mailbox adapters are removed. TOM supports a private development mailbox and configurable SMTP. No delivery-acknowledgment protocol or EP notification queue is required.


Browser → TOM (Rails / Phlex / Tailwind) → EP (Phoenix) → EP PostgreSQL.

TOM is a backend for its browser UI. Its only application integration is EP's JSON API. It has no Active Record, database configuration, SQL gems, workers or business-data cache. Local logs, assets and the encrypted session cookie are operational state, not independent authoritative data.

`Ep::Client` owns a fixed configured HTTP(S) origin, explicit API operations, bounded timeouts and sanitized failures. `SessionsController` requests verification through EP and resets the session before saving its Bearer token. Controllers use `layout false`; `Views::Base#around_template` wraps each Phlex view in `Components::Layout`. Phlex forms use Rails form builders and CSRF tokens without ERB or JavaScript.

EP alone validates identity, permissions, tenant membership and idempotent commands. Tenant views always query EP; they do not store or reconstruct domain facts. No generic proxy or direct database access exists. Navigation supports authorized tenant IDs until EP supplies an access-filtered list. No role is guessed from a successful request.

Rails' encrypted HttpOnly cookie avoids a session database while keeping bearer values inaccessible to JavaScript. It is not server-side persistence and does not prevent replay of a copied cookie; expiry and future EP-side revocation remain essential. Logout currently clears only the TOM browser session. HTTPS and a protected shared SECRET_KEY_BASE are required for deployment.

CreateTenant uses a server-generated session key sent as `Idempotency-Key`. It survives failures so an uncertain write can be retried. Successful responses rotate it. An altered payload under that key is rejected by EP; TOM never silently changes keys to bypass a conflict.

No PWA/offline caching, automatic POST retries, a connected production email provider or administrator editing is implied by this slice. The app may scale independently of EP; concurrency and production load remain unmeasured.


Occasion creation is nested under a verified tenant route. The form preflight lists occasions through EP to check tenant-admin access. EP independently revalidates the write. A tenant-bound session key is forwarded for idempotency. The request allowlist contains name, slug, UTC expiry timestamp and optional self admin assignment; scope and actor fields cannot be overridden by the browser. Name/slug/expiry failures render the form again without changing its key. The tenant overview and occasion detail consume EP's dedicated occasion-directory MV. No occasion tables or grants exist in TOM.


Tenant-admin invitations are owned entirely by EP. TOM stores only a tenant-bound creation idempotency key in its encrypted session, renders the current tenant-admin invitation list and provides a verified-recipient inbox. Accept/revoke use deterministic per-invitation command keys plus Rails CSRF protection. A browser-supplied role, recipient identity or grant state is never forwarded. EP’s bounded synchronous invitation guard is the deliberate source for actionable lifecycle/inbox queries; grant mutation and authority checks are transactional. Invitation delivery material is returned to the authorized caller; TOM sends messages linking to its own invitation inbox.

Seven-day expiry is the initial implementation policy. Current sponsor authority and recipient email verification are required at acceptance. Invitation revocation never removes an already accepted administrator. Admin-removal/last-admin recovery, production email delivery and invitation privacy cleanup remain separate work.


Occasion invitations reuse the EP invitation lifecycle, with optional tenant-parented occasion scope. TOM’s shared management controller/view selects only the route scope; the creation key is bound to tenant and occasion. Tenant and occasion inbox queries are combined into clearly labelled cards. Occasion acceptance redirects to that exact occasion, while accepted cards provide subsequent navigation only when EP confirms the current grant and parent lifecycle. EP supplies a current `can_manage_admins` capability for displaying invitation controls; possession of the occasion grant itself does not authorize further admin invitations. No participant membership or tenant grant is inferred from accepting an occasion invitation.


Recruitment administrative actions use a tenant-and-occasion-bound session key and EP's current guard-state endpoint. Public publication reads the incremental occasion MV only after EP checks current lifecycle, expiry, open state and policy-version alignment. A stale open view cannot permit intake after closure. EP's application command independently rechecks open state and exact policy version inside the transaction, while holding a shared occasion-row lock against exclusive lifecycle transitions.

TOM forwards only title/instructions/notice URL/manual-policy confirmation, closure reason or application notice acknowledgment/version. Identity and scopes come from EP verification and routes. Public GET establishes only a local recruitment return path for subsequent verified sign-in; it never consumes URL credentials or grants access. The browser uses CSRF-protected forms and an encrypted HttpOnly session. Applications are pending-only guards with no admission endpoint; admin queue access remains scoped. Full workforce/safeguarding/retention readiness is not implied by opening this local expression-of-interest form.


Authentication challenge issuance and redemption now require `X-EP-Backend-Token`, with secrets provisioned by the operator separately in each app. Challenges are hashed in EP and bound to the issuing backend. TOM creates message links from `TOM_PUBLIC_BASE_URL`, stages incoming tokens in its encrypted cookie and requires CSRF-protected confirmation POSTs, preventing email-scanner GET requests from signing users in. SMTP/file transport is TOM-owned and synchronous; no EP delivery worker, shared mailbox or acknowledgment protocol remains. The local provisioning CLI copies configuration once; the applications never read each other's files at runtime.

Invitation API responses include current delivery material outside event/receipt persistence. An uncertain/failed invitation send retains the caller's idempotency key; retry returns the same invitation if still live. Magic-link issuance instead explicitly creates a fresh challenge and invalidates the preceding one for that backend, so it is never silently retried. SMTP errors are sanitized and tokens/provider secrets stay out of browser HTML/logs. Backend misconfiguration is a service failure rather than a user-session revocation.

Returning-admin navigation comes from current grant-filtered, running tenant/occasion projections. A new sign-in preserves the canonical identity and does not repeat tenant/occasion admin grants. EP still authorizes every subsequent operation.
