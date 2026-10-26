# Requirements

- TOM is an independent Rails application under `systems/tom`, styled with Tailwind and rendered with Phlex.
- TOM has no database; all authentication, business commands, authorization and query data belong to EP.
- Support email sign-in, tenant creation and opening an authorized tenant, including pending/unavailable states.
- Keep credentials out of browser JavaScript and URLs; enforce CSRF, private responses and secure production cookies.
- Preserve tenant isolation and command idempotency through EP; never invent UI-side permissions.

- Tenant admins can create occasions with a name, tenant-unique short name, future expiry review date and an optional self occasion-admin grant; no participant membership or recruitment opening is implied.
- Show occasion lists and pending/ready details from EP; EP enforces parent binding and current grants.

- Tenant admins can invite prospects by email, review recent invitations and revoke pending invitations. Prospects must verify the intended email and explicitly accept before EP grants tenant-admin access.
- Invitations expire after seven days; EP rechecks sponsor authority and serializes acceptance/revocation. No invitation ID is a credential.

- Tenant admins can invite occasion-admin prospects, with verified-recipient acceptance, seven-day expiry and pending revocation restricted to the named tenant and occasion.
- Acceptance must not grant tenant access or create participant membership. Occasion admins cannot issue admin invitations without separate tenant authority.
- Accepted recipients can return directly to authorized occasions without navigating the tenant overview.

- Tenant admins and the current occasion admins explicitly open and close recruitment with published instructions, a privacy-notice link and a fixed pending-manual-review policy.
- Verified prospects may submit one minimal expression of interest per occasion after notice acknowledgment; EP grants no membership or assignment.
- Closing/expiry blocks intake immediately; stale policy versions and unauthorized sibling operations are rejected by EP.

- The API response is EP's contract with application backends: an authorized invitation/challenge request returns the result and necessary delivery material to its calling backend. A future MCP interface preserves these same rules.
- TOM owns rendering and delivering its invitation/authentication messages, including provider handling; EP owns scoped state, verification, expiry, revocation and command idempotency. No shared mailbox, mandatory delivery queue or separate acknowledgment protocol is required.
- Raw authentication secrets must not enter ordinary events, MVs or logs. Returning delivery material is restricted to authorized backend callers and does not weaken recipient verification or anti-enumeration controls.

- EP issuance/redemption and invitation creation delivery responses are restricted by an operator-provisioned backend API credential, in addition to applicable user authority. Authentication secrets are bound to their issuing backend.
- TOM constructs clickable messages from its configured public origin and sends using its own SMTP/file provider. Magic-link GET requests only stage confirmation; redemption requires a CSRF-protected POST.
- A failed invitation send retains its command key for safe retry. A later sign-in rediscovers current tenant/occasion navigation without creating new identities or grants.

- Capture safe code/input/dependency/delivery outcomes through EP's monitoring API with request correlation and EP-verified reporting scope; local evidence remains available if persistence fails.
- Provide authorized tenant/occasion monitoring lists, freshness, issue timelines and idempotent versioned operator actions without a TOM database.
- Use Turbo Streams for in-context failures/status updates, preserve ordinary input and reconcile uncertain accepted commands without automatically repeating them; keep credentials and raw diagnostic text out of feedback.

## Monitoring operations (local implementation)

Local monitoring must survive EP outages through a bounded encrypted transport queue, with independent probes and explicit loss accounting. Scope administrators manage reporting sources and alert rules through EP; restricted diagnostics/platform access require explicit grants. Alert delivery belongs to a separately supervised TOM worker with terminal outcome acknowledgments and no automatic resend of ambiguous attempts.
