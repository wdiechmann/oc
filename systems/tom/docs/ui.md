# UI and API

- `/session/new`: email form plus single-use sign-in token form. Development instructions point to EP's private mailbox; TOM never reads that directory.
- `/`: authenticated tenant creation and open-by-UUID forms. Retains the most recently opened UUID as a convenience.
- `/tenants/:id`: EP-authorized tenant name, readiness and projection version; explicit refresh for pending processing.
- Sign out: removes TOM's encrypted browser session. EP revocation is not yet implemented.
- `/up`: process liveness.

TOM server calls only these EP endpoints: POST `/api/v1/auth/magic-links`, POST `/api/v1/auth/magic-links/verify`, POST `/api/v1/tenants` with an Idempotency-Key, GET `/api/v1/tenants/:id` with Bearer authentication. Browser forms use Rails authenticity tokens. Bearer credentials are neither rendered nor sent directly by browser JavaScript.

The interface uses responsive Phlex components, semantic headings, explicit labels, keyboard focus states and Tailwind utilities. It requires no JavaScript runtime, external fonts or third-party browser services.
