# Architecture

VERA owns its web presentation and client session; EP owns canonical identity, authorization, accepted facts, transactional finance guards and query projections. The app intentionally excludes Active Record/Active Job/Action Cable and has no database configuration. No runtime dependency on TOM is introduced.

`HomeController → Views::Home::Index → Components::Layout` renders the static shell without calling EP. `EpHealthController → Ep::Client → EP /health/ready` provides dependency readiness using a fixed configured HTTPS origin or loopback HTTP origin, short timeouts, no redirect following and no automatic retries. A response must be 200 JSON with status ready. No browser credentials are forwarded. Authenticated business operations and source registration are not yet implemented.

Phlex uses explicit Views and Components autoload namespaces; Turbo and Tailwind assets are served locally. A content-security policy permits same-origin scripts/styles with a style nonce for Turbo, and arbitrary request parameters are filtered from logs. VERA uses its own Rails secrets and future backend credential; there is no shared TOM cookie/secret store. Production requires its own deployment secrets and HTTPS configuration.
