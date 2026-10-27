# Requirements

VERA is a separate client for financial control, accounting and settlement. It must use EP APIs for accepted data and current authorization, with no local business database. Books and their nesting are financial contexts using the same underlying tables and associations, as specified in ../../finance.md.

The initial foundation provides a public Phlex/Tailwind shell, locally served Turbo and separate application/dependency health checks. It must start independently of EP and coexist with TOM on a different port. Financial functionality requires a subsequent authenticated, scoped EP contract.

Sign-in is a thin EP-backed operation for an existing identity. Signup, invitations, recovery and identity administration remain in TOM. Require backend-bound single-use links, explicit confirmation, generic unknown/throttled responses, a private VERA session, current EP workspace checks and own-session revocation. No duplicate identity store or shared TOM cookie/credential is permitted.
