# Authentication API — thin application sign-in

[OpenAPI contract](authentication-openapi.json). EP remains the authority for canonical identity and API sessions. TOM provides identity signup, invitations and administration; a client such as VERA needs only an existing-identity sign-in form and its own session. This is not shared-cookie SSO: being signed into TOM does not automatically sign the browser into VERA.

| Endpoint | Caller | Result |
|---|---|---|
| `POST /api/v1/auth/sign-in-links` | Registered backend credential, `{email}` | 202 `{status: "check_your_email", delivery: material-or-null}`. Issues only for an active verified existing identity. Unknown addresses and throttled requests return the same generic status with null delivery. |
| `POST /api/v1/auth/magic-links/verify` | Same requesting backend credential, `{token}` | 200 `{token, token_type: "Bearer", expires_at}`. Single-use challenge, 15-minute lifetime; wrong backend, expired/used challenge, suspended identity or changed identity/email binding returns 401. |
| `DELETE /api/v1/auth/session` | Registered backend credential plus current user Bearer | 200 `{status: "signed_out"}`; revoke only this session. Repeating after revocation returns 401; other app/user sessions are untouched. |
| `GET /api/v1/me/workspaces` | Current user Bearer | Authorized tenant/occasion navigation, revalidated against current session, identity and grants. No financial permission is implied by navigation. |

The existing `POST /api/v1/auth/magic-links` signup-capable flow remains available to trusted backends and is used by TOM. VERA uses the sign-in-only endpoint; unknown-user requests cannot establish an identity through that path. Sign-in-only challenges retain a protected existing-identity reference and verify its current email/status, rather than establishing a new identity or following a reassigned email to someone else. Sharing the identity does not duplicate memberships or grants.

`X-EP-Backend-Token` authenticates the calling backend; it is not a browser/user credential. Each application needs its own secret binding. A backend credential is the current trusted-caller gate, not a completed application-purpose/capability registry. User authorization remains independently checked. No backend secret, raw magic link or API token belongs in ordinary events, query views, logs, URLs to unrelated apps or the rendered page.

Delivery material is protected handoff data: `{email,token,expires_at}`. The requesting application constructs its own configured URL and delivers it. A returned challenge is not evidence of delivery. Only hashes are retained as verification credentials in EP. All responses are no-store; invalid email is 422, missing/invalid backend is 401 (503 when unconfigured), invalid/expired session is 401 and infrastructure failure is safely reported. The API's generic public response must not expose whether an address exists.

Clients should stash a well-formed link token in their own protected pre-login session on GET, then redeem it only on an explicit CSRF-protected POST. Rotate that session after verification. Keep raw EP Bearers in the application's encrypted HttpOnly cookie or equivalently protected session, with expiry and current EP checks; never store role claims as authorization. Lost responses do not prove rejection and HTTP clients must not automatically retry issuance/verification. A new request is explicit; prior outstanding challenges for the same backend/email are invalidated. The existing limit is three issued challenges per email in 15 minutes across backends.

On logout, clear the browser session even if EP is unavailable, but say if server-side revocation was not confirmed. Do not claim to have signed the user out of TOM or every application. Provider delivery, application URLs, session encryption and deployment configuration belong to each calling backend; identity lifecycle and later recovery policy remain shared platform/TOM responsibilities.

## Local registration

`systems/vera/bin/provision-ep-backend` is an operator setup command, not a runtime integration: it creates/retains a separate VERA credential in private ignored VERA/EP configuration files without changing TOM's credential. EP development merges `config/backend_api_tokens.json` with its primary backend and then environment overrides. Production reads no such local file; provide independent entries through `EP_BACKEND_TOKENS_JSON` and application secrets. Restart processes after configuration/dependency changes; migrate EP before using sign-in-only binding. Never copy one backend's token to another application to bypass registration.
