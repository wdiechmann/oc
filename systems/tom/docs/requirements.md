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
