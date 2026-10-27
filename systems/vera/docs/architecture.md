# Architecture

VERA owns its web presentation and client session; EP owns canonical identity, authorization, accepted facts, transactional finance guards and query projections. The app intentionally excludes Active Record/Active Job/Action Cable and has no database configuration. No runtime dependency on TOM is introduced.

`HomeController → Views::Home::Index → Components::Layout` renders the static shell without calling EP. `EpHealthController → Ep::Client → EP /health/ready` provides dependency readiness using a fixed configured HTTPS origin or loopback HTTP origin, short timeouts, no redirect following and no automatic retries. A response must be 200 JSON with status ready. No browser credentials are forwarded. Authentication is implemented as described below; financial commands and monitoring-source registration remain next work.

Phlex uses explicit Views and Components autoload namespaces; Turbo and Tailwind assets are served locally. A content-security policy permits same-origin scripts/styles with a style nonce for Turbo, and arbitrary request parameters are filtered from logs. VERA uses its own Rails secrets and future backend credential; there is no shared TOM cookie/secret store. Production requires its own deployment secrets and HTTPS configuration.

## Thin sign-in

VERA POSTs /api/v1/auth/sign-in-links with its own backend credential. EP issues only for an active verified existing identity and binds the challenge to that identity and requesting backend. GET /session/verify stores the short-lived pending value in VERA's encrypted HttpOnly cookie; POST /session confirms through EP's existing verification API. Session rotation drops pre-login state; only the opaque EP session and expiry are retained. EP checks identity/session and current grants on protected calls. GET /me/workspaces provides current navigation, not a financial permission grant.

DELETE /api/v1/auth/session revokes only the presented session. VERA clears its cookie even if EP is unreachable, with an uncertainty notice. TOM's independent session remains valid. No SSO redirect protocol, shared cookie or duplicate invitation/recovery workflow is added. VERA delivers its own ephemeral sign-in message as the calling backend under the existing EP API handoff contract.

Local operator setup creates matching private configuration copies for EP's `vera` registration and VERA's own credential. Production uses deployment secrets and HTTPS application origins. Exceptions/parameters are sanitized and known form errors stream into vera-feedback. Full operational monitoring ingestion remains pending.
