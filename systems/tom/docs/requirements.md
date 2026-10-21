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
