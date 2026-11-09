# Named Spaces

This document identifies candidate named spaces—business or operational bounded contexts—derived from [`domain.md`](domain.md). A space may eventually be implemented as a module, service, product area, or set of cooperating components; the names describe domain responsibility rather than a mandatory deployment architecture.

## Shared foundation spaces

### Identity and access

Required identities for human and mechanical/electronic contacts; optional identities for organizational contacts; verified human email/phone login identifiers, machine credentials, and multi-user organizational identity access through attributable delegation. Controlled lifecycle, roles, permissions, authorization scopes, and delegated administration.

### Contacts and organizations

Canonical human, mechanical/electronic and organization contacts, administrator-defined contact-type tags, contact hierarchies, relationship types, contact provenance, and shared relationship references.

### Occasions and tenancy

Tenant signup/creation, first and delegated tenant admins, tenant-wide access, and tenant lifecycle. Occasions within tenants, occasion admins, recruitment opening, occasion-specific configuration and lifecycle, and isolation between tenants and sibling occasions.

### Memberships and teams

Occasion memberships, optional role contexts, team hierarchies, team membership, inherited assignments, and participation relationships.

### Data integration and platform services

APIs, events, imports, synchronization, master data, external references, search, workflows, notifications, audit trails, offline reconciliation, observability, and data-quality controls.

## Participation and relationship spaces

### Participant registration and safeguarding

Occasion sign-up, participant answers, health and allergy information, consent, guardian workflows, scout-organization member-service imports, safe-from-harm evaluation, and safeguarding follow-up.

### CRM and relationship management

Contacts, organizations, participants, families, suppliers, sponsors, authorities, relationship ownership, interaction history, cases, campaigns, communication preferences, and follow-up.

### Volunteer and occasion workforce management

Recruitment, applications, interviews, screening, skills, qualifications, onboarding, assignments, shifts, attendance, satisfaction, wellbeing, performance, offboarding, and workforce reporting.

### Occasions and activities management

Activity design, approval, publication, participant sign-up, capacity, waitlists, staffing, equipment, materials, safety, attendance, feedback, right-sizing, and activity performance.

## Planning and place spaces

### GIS-enabled camp planning and operations

Camp design, geographic features, infrastructure, capacity planning, design versions, operational map layers, closures, resources, real-time conditions, and map-based dispatch.

### Calendar, scheduling, and capacity management

Shifts, venues, vehicles, equipment, teams, appointments, training, deliveries, maintenance, inspections, dependencies, conflicts, resource bookings, and capacity constraints.

### Arrival and departure logistics

Arrival and departure slots, people and goods manifests, gates, routes, staging areas, loading and unloading, throughput, exceptions, and movement plans.

### Transport and traffic management

Vehicles, permits, parking, shuttles, deliveries, waste collection, traffic flow, congestion, route closures, emergency access, dispatch, and transport performance.

## Supply, infrastructure, and environment spaces

### Supply-chain management

Demand planning, work packages, bills of materials, procurement requests, suppliers, purchase orders, deliveries, substitutions, replenishment, readiness, and post-occasion disposition.

### Stock and asset management

Asset definitions, stock units, reservations, locations, movements, participant orders, bills of materials, picklists, issuing, return inspection, maintenance, losses, damage, and invoicing.

### Facilities and utilities management

Facilities, tents, buildings, containers, roads, utilities, installation, commissioning, operations, inspections, maintenance, outages, breakdowns, dismantling, return, refurbishment, and disposal.

### Environmental and food-safety monitoring

Water, air, food-handling conditions, sanitation, waste, weather, sensors, inspections, measurements, thresholds, alerts, compliance, and corrective-action tickets.

### Food-service and catering management

Menus, meal offerings, kitchens, serving points, demand forecasts, dietary and allergy requirements, production, food inventory, staffing, distribution, waste, hygiene, and meal reporting.

## Operations and safety spaces

### Occasion operations and support tickets

Participant support, operational requests, incidents, observations, work items, categories, priority, severity, assignment, escalation, service levels, locations, and resolution history.

### Emergency and incident command

Major-incident declaration, command roles, response plans, operational periods, objectives, situation reports, resource requests, decisions, briefings, handovers, restricted information, and post-incident review.

### Security, access control, and threat prevention

Credentials, access grants, restricted zones, gates, checkpoints, visitors, vehicles, perimeter monitoring, guard observations, lost wristbands, security incidents, evidence, and emergency overrides.

### Closed-loop occasion communications

All-participant alarms, targeted alerts, direct messages, team messaging, rich messages, delivery receipts, acknowledgements, audio/video streams, conferencing, moderation, and emergency-priority traffic.

## Financial and commercial spaces

### Closed-loop occasion payments

RFID wristbands, occasion payment accounts, reader applications, internal transaction authorization, balances, limits, refunds, transfers, top-ups, replacement, reconciliation, and settlement.

### Financial and economic planning and execution

Budgets, forecasts, cost centers, financial obligations, participant charges, damaged-asset invoices, supplier invoices, sponsor funding, reimbursements, payroll-like settlements, payments, reconciliation, reporting, and audit.

### Fundraising and sponsor management

Sponsor prospects, opportunities, proposals, agreements, financial and in-kind commitments, sponsor benefits, fulfillment, branding, relationship development, renewals, conflicts, and sponsor-value reporting.

## Knowledge and learning spaces

### Document, knowledge, and procedure management

Runbooks, safety procedures, maps, forms, policies, training material, templates, ownership, review, approval, publication, versioning, effective dates, acknowledgement, search, and offline guidance.

### Performance, learning, and knowledge management

Cross-system telemetry, response times, correctness, errors, utilization, satisfaction, safety, financial performance, forecasts, KPIs, quality evaluations, AI-assisted insights, recommendations, lessons learned, and post-occasion analysis.

## Cross-space relationships

The following shared references connect most spaces:

- **Contact and identity** — who a person or organization is
- **Tenant > occasion** — owning workspace and the undertaking where and when the relationship applies
- **Membership and team** — in which occasion context the party operates
- **Role and permission** — what the party may do
- **Location and GIS feature** — where an activity, asset, ticket, incident, or service applies
- **Time and schedule** — when an operation is planned or executed
- **Asset, resource, and capacity** — what is required, available, reserved, or consumed
- **Ticket, incident, and activity** — what work or participation is occurring
- **Financial obligation and transaction** — what economic consequence is created
- **Document and procedure** — which approved guidance applies
- **Audit and performance record** — what happened, how well it worked, and what was learned
