# Architecture

Browser → TOM (Rails / Phlex / Tailwind) → EP (Phoenix) → EP PostgreSQL.

TOM is a backend for its browser UI. Its only application integration is EP's JSON API. It has no Active Record, database configuration, SQL gems, workers or business-data cache. Local logs, assets and the encrypted session cookie are operational state, not independent authoritative data.

`Ep::Client` owns a fixed configured HTTP(S) origin, explicit API operations, bounded timeouts and sanitized failures. `SessionsController` requests verification through EP and resets the session before saving its Bearer token. Controllers use `layout false`; `Views::Base#around_template` wraps each Phlex view in `Components::Layout`. Phlex forms use Rails form builders and CSRF tokens without ERB or JavaScript.

EP alone validates identity, permissions, tenant membership and idempotent commands. Tenant views always query EP; they do not store or reconstruct domain facts. No generic proxy or direct database access exists. Navigation supports authorized tenant IDs until EP supplies an access-filtered list. No role is guessed from a successful request.

Rails' encrypted HttpOnly cookie avoids a session database while keeping bearer values inaccessible to JavaScript. It is not server-side persistence and does not prevent replay of a copied cookie; expiry and future EP-side revocation remain essential. Logout currently clears only the TOM browser session. HTTPS and a protected shared SECRET_KEY_BASE are required for deployment.

CreateTenant uses a server-generated session key sent as `Idempotency-Key`. It survives failures so an uncertain write can be retried. Successful responses rotate it. An altered payload under that key is rejected by EP; TOM never silently changes keys to bypass a conflict.

No PWA/offline caching, automatic POST retries, production email adapter, tenant-list API or administrator editing is implied by this slice. The app may scale independently of EP; concurrency and production load remain unmeasured.


Occasion creation is nested under a verified tenant route. The form preflight lists occasions through EP to check tenant-admin access. EP independently revalidates the write. A tenant-bound session key is forwarded for idempotency. The request allowlist contains name, slug, UTC expiry timestamp and optional self admin assignment; scope and actor fields cannot be overridden by the browser. Name/slug/expiry failures render the form again without changing its key. The tenant overview and occasion detail consume EP's dedicated occasion-directory MV. No occasion tables or grants exist in TOM.


Tenant-admin invitations are owned entirely by EP. TOM stores only a tenant-bound creation idempotency key in its encrypted session, renders the current tenant-admin invitation list and provides a verified-recipient inbox. Accept/revoke use deterministic per-invitation command keys plus Rails CSRF protection. A browser-supplied role, recipient identity or grant state is never forwarded. EP’s bounded synchronous invitation guard is the deliberate source for actionable lifecycle/inbox queries; grant mutation and authority checks are transactional. Notifications are durable EP jobs with private development delivery and no credential links.

Seven-day expiry is the initial implementation policy. Current sponsor authority and recipient email verification are required at acceptance. Invitation revocation never removes an already accepted administrator. Admin-removal/last-admin recovery, production email delivery and invitation privacy cleanup remain separate work.


Occasion invitations reuse the EP invitation lifecycle, with optional tenant-parented occasion scope. TOM’s shared management controller/view selects only the route scope; the creation key is bound to tenant and occasion. Tenant and occasion inbox queries are combined into clearly labelled cards. Occasion acceptance redirects to that exact occasion, while accepted cards provide subsequent navigation only when EP confirms the current grant and parent lifecycle. EP supplies a current `can_manage_admins` capability for displaying invitation controls; possession of the occasion grant itself does not authorize further admin invitations. No participant membership or tenant grant is inferred from accepting an occasion invitation.


Recruitment administrative actions use a tenant-and-occasion-bound session key and EP's current guard-state endpoint. Public publication reads the incremental occasion MV only after EP checks current lifecycle, expiry, open state and policy-version alignment. A stale open view cannot permit intake after closure. EP's application command independently rechecks open state and exact policy version inside the transaction, while holding a shared occasion-row lock against exclusive lifecycle transitions.

TOM forwards only title/instructions/notice URL/manual-policy confirmation, closure reason or application notice acknowledgment/version. Identity and scopes come from EP verification and routes. Public GET establishes only a local recruitment return path for subsequent verified sign-in; it never consumes URL credentials or grants access. The browser uses CSRF-protected forms and an encrypted HttpOnly session. Applications are pending-only guards with no admission endpoint; admin queue access remains scoped. Full workforce/safeguarding/retention readiness is not implied by opening this local expression-of-interest form.
