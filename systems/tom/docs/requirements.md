# Requirements

- TOM is an independent Rails application under `systems/tom`, styled with Tailwind and rendered with Phlex.
- TOM has no database; all authentication, business commands, authorization and query data belong to EP.
- Support email sign-in, tenant creation and opening an authorized tenant, including pending/unavailable states.
- Keep credentials out of browser JavaScript and URLs; enforce CSRF, private responses and secure production cookies.
- Preserve tenant isolation and command idempotency through EP; never invent UI-side permissions.
