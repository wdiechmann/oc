# Architecture

Browser → TOM (Rails / Phlex / Tailwind) → EP (Phoenix) → EP PostgreSQL.

TOM is a backend for its browser UI. Its only application integration is EP's JSON API. It has no Active Record, database configuration, SQL gems, workers or business-data cache. Local logs, assets and the encrypted session cookie are operational state, not independent authoritative data.

`Ep::Client` owns a fixed configured HTTP(S) origin, explicit API operations, bounded timeouts and sanitized failures. `SessionsController` requests verification through EP and resets the session before saving its Bearer token. Controllers use `layout false`; `Views::Base#around_template` wraps each Phlex view in `Components::Layout`. Phlex forms use Rails form builders and CSRF tokens without ERB or JavaScript.

EP alone validates identity, permissions, tenant membership and idempotent commands. Tenant views always query EP; they do not store or reconstruct domain facts. No generic proxy or direct database access exists. Navigation supports authorized tenant IDs until EP supplies an access-filtered list. No role is guessed from a successful request.

Rails' encrypted HttpOnly cookie avoids a session database while keeping bearer values inaccessible to JavaScript. It is not server-side persistence and does not prevent replay of a copied cookie; expiry and future EP-side revocation remain essential. Logout currently clears only the TOM browser session. HTTPS and a protected shared SECRET_KEY_BASE are required for deployment.

CreateTenant uses a server-generated session key sent as `Idempotency-Key`. It survives failures so an uncertain write can be retried. Successful responses rotate it. An altered payload under that key is rejected by EP; TOM never silently changes keys to bypass a conflict.

No PWA/offline caching, automatic POST retries, production email adapter, tenant-list API, occasion API or administrator editing is implied by this slice. The app may scale independently of EP; concurrency and production load remain unmeasured.
