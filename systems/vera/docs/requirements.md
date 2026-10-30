# Requirements

VERA is a separate client for financial control, accounting and settlement. It must use EP APIs for accepted data and current authorization, with no local business database. Books and their nesting are financial contexts using the same underlying tables and associations, as specified in ../../finance.md.

The initial foundation provides a public Phlex/Tailwind shell, locally served Turbo and separate application/dependency health checks. It must start independently of EP and coexist with TOM on a different port. Financial functionality requires a subsequent authenticated, scoped EP contract.

Sign-in is a thin EP-backed operation for an existing identity. Signup, invitations, recovery and identity administration remain in TOM. Require backend-bound single-use links, explicit confirmation, generic unknown/throttled responses, a private VERA session, current EP workspace checks and own-session revocation. No duplicate identity store or shared TOM cookie/credential is permitted.

## Tenant books — first delivery

Active tenant administrators can create/list/view draft book contexts and revise names/parent relationships through EP. All levels use the same schema. Require tenant-local unique codes, current session/grants, cycle-safe hierarchy, expected book versions, idempotency and no local authoritative persistence. This bootstrap authority covers metadata only; financial permissions remain separate. Provide pending/stopped query states, protected-region clearing after revocation and lost-response receipt reconciliation.

## Book-scoped finance configuration

Tenant administrators explicitly assign/revoke configuration stewards for individual books, including themselves. Administration alone permits inspection/role assignment, not account or binding changes. Stewardship neither inherits across parent/child books nor grants approval/posting/payment authority. Current identities, sessions, tenant status and protected grant state govern every command before replay.

A steward can bind/unbind this tenant's occasions and list/create/revise/deactivate/reactivate accounts. An occasion has at most one applicable book; several occasions may share it. Moving requires explicit release from the previous book. Account IDs equal their AccountCreated event IDs; numbers are strings with leading zeroes, and old/inactive numbers remain reserved. Heading/total rows are labels without formulas in this slice. Protect setup/account versions and use idempotent commands with private receipts. Preserve conflicting drafts above the newer accepted account, with actor/application/revision and explicit reapplication. Unknown saves block new changes; completion checks never repeat writes. An explicit retry after checking uses only the original unchanged command and key.
