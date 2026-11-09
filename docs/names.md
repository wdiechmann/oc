# Naming stuff

Product names and their responsibilities, based on the project documentation. System numbers refer to [suggested_systems.md](suggested_systems.md), not implementation-plan filenames.

## EP

**Event Protocol** — the shared backend and acceptance contract used by the applications.

- Canonical identity, current authorization and tenant/occasion scope enforcement
- Validated commands, accepted events and transactionally protected domain state
- Idempotency receipts, durable publication and background-maintained materialized views
- Scoped APIs for application queries and domain operations

EP is the existing Elixir/Phoenix and PostgreSQL application in `systems/ep`. It supplies the platform foundation associated with **system 21**, alongside domain handlers for system 1, finance and other implemented slices. EP is a shared backend, not a user-facing replacement for TOM, VERA or ASTER. Application backends own provider execution and message delivery through explicit API handoffs.

Sources: [EP README](../systems/ep/README.md), [Architecture](architecture.md), [Data-store design](suggested-data-store.md).

## TOM

**Tenant & Occasion Management** — the administration application for the shared identity and organization control plane.

- Signup, sign-in and canonical identity access
- Tenant creation and tenant-admin invitations
- Occasion creation and occasion-admin invitations
- Authorized workspace navigation and recruitment opening/closure
- Scoped operational monitoring and alert administration

TOM is the existing Rails/Phlex/Tailwind application in `systems/tom`. It calls EP APIs; EP owns identity, authorization and accepted business state, while TOM owns its interface and message delivery. It implements the administration-facing slice of **system 1**, with monitoring capabilities supporting systems 20/21; it is not the complete implementation of those systems.

Sources: [TOM README](../systems/tom/README.md), [System 1 plan](system_1_plan.md), [Monitoring plan](monitoring_plan.md).

## VERA

**Financial Control, Accounting and Settlement** — the finance application. The existing documentation establishes this product description but does not define an expansion of the letters VERA.

- Accounting books and nested book structures
- Chart of accounts, classifications, VAT configuration and accounting periods
- Planned budget and commitment controls, journals, approvals and posting
- Planned receivables/payables, settlement, reconciliation and financial reporting
- Later closed-loop occasion payments and accounting integrations

VERA is the existing separate Rails/Phlex/Tailwind application in `systems/vera`, using EP APIs without a local business database. Its scope primarily delivers **system 13 — Billing and accounting integration**, followed by **system 12 — Closed-loop payments and occasion finance**. The filename `system_2_plan.md` denotes implementation plan 2; VERA is not catalogue system 2. Financial setup is implemented incrementally; the complete finance and payment scope remains planned.

Sources: [VERA README](../systems/vera/README.md), [Finance plan](system_2_plan.md), [Finance requirements](finance.md).

## ASTER

A fresh, modern name meaning "star"

- Assignment & Work orders
- Service levels
- Ticketing & Escalation
- Experience (Participant Support)
- Resolution tracking

**Ticketing and Service Management** — the name recorded here for **system 5**. The five capability lines above give the A–S–T–E–R mnemonic.

ASTER starts with the shared WorkItem planning spine: tasks, accountable owners, dependencies, due dates and restricted review queues. It then extends to participant intake, triage, conversations, accepted assignments, work orders, service-level policies, escalation and resolution history. Tickets present the shared work model rather than introducing a separate work hierarchy.

Participant Experience and Programme owns common intake and the service-management process; each portfolio owns assigned resolution. Safety owns restricted incident classification and escalation into system 6. ASTER coordinates that handoff without taking ownership of emergency command.

ASTER is planned. The system 5 plan proposes a separate application using EP APIs and the existing Rails/Phlex/Tailwind pattern; it does not establish an implemented ASTER application.

Sources: [System 5 plan](system_5_plan.md), [Shared entity model](entity-relationship.md), [Organization and ownership](organization.md).
