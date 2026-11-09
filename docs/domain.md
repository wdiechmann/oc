# Occasion Compass — Domain Model

Occasion Compass, OC (Oh-See /oʊ ˈsiː/ )

## Context

**Terminology:** An **occasion** is an organized camp such as Spejdernes Lejr 2030; `Occasion` is its canonical entity. An **event** is a recorded domain fact or operational occurrence. A tenant is the owning individual/organization workspace; an occasion belongs to one tenant. The scope hierarchy is **tenant > occasion > event**, while event IDs identify individual recorded facts.

Spejdernes Lejr 2030 will be a national jamboree, similar in scale and character to the jamboree held at Hedeland in 2026. Its digital support structures will need to support both the occasion itself and the business-like operations required to plan and run it.

The platform is expected to cover areas such as:

- Supply-chain and logistics management
- Payment processing
- Closed-loop participant payments
- Ticketing and registration
- Participant registration and safeguarding
- CRM and relationship management
- Customer and participant support
- Occasion operations, incidents, and support tickets
- Emergency and incident command
- Closed-loop occasion communications
- Environmental and food-safety monitoring
- GIS-enabled camp planning, design, and operations
- Volunteer and occasion workforce management
- Fundraising and sponsor management
- Arrival and departure logistics
- Transport and traffic management
- Food-service and catering management
- Calendar, scheduling, and capacity management
- Performance, learning, and knowledge management
- Document, knowledge, and procedure management
- Data integration and occasion-platform services
- Financial and economic planning and execution
- Occasions and activities management
- Stock and asset management for reusable occasion equipment
- Additional operational, communication, volunteer, and reporting capabilities as the domain develops

## Areas in greater details

### Assets and stock management

Assets are reusable or consumable items acquired for earlier occasions and held ready for deployment at a future camp or occasion. The stock-management system must support the complete lifecycle of an asset from available stock through allocation, issue, return, inspection, and either restocking or financial settlement.

Signed-up campers and volunteers may order assets within the permissions and operational rules of their membership, team, or role context. An asset order should produce an order record and a bill of materials describing the requested items and quantities.

For pre-camp operations, confirmed orders should produce picklists for personnel operating the stock. Picklists should identify the assets and quantities to retrieve, the recipient or destination, and the status of each picking and handover operation.

After the occasion, issued assets should produce return-to-stock lists. Returned items must be inspected and classified as accepted back into stock, missing or not returned, damaged or otherwise not in stockable condition, or awaiting inspection or resolution.

Assets that are missing or not accepted in stockable condition may result in an invoice or other charge to the responsible party. The system should retain the relationship between the original order, issued items, return inspection, charge decision, and resulting invoice.

Stock management should distinguish the asset definition from individual stock units where tracking, condition, serial numbers, ownership, or maintenance requires it. It should also support stock levels, reservations, locations, movements, condition, and occasion-specific availability.

### Participant registration and safeguarding

Participants—including campers, volunteers, camp management, and other occasion roles—must sign up for the occasion through a registration process. Registration establishes the participant's occasion membership and collects the information required to safely and effectively support their participation.

The registration process may include:

- Occasion-specific participation and role information
- Health, allergy, dietary, accessibility, and other wellbeing information
- Preferences and practical requirements
- Emergency-contact information and relevant consent records
- Safeguarding information and a **safe from harm** evaluation

The safe-from-harm evaluation is performed in concert with relevant government bodies. The domain must support the exchange of the required information, evaluation status, decisions, follow-up actions, and audit history while respecting the applicable legal and organizational requirements.

If a participant states that they are a scouting member of a named organization, and provides the required consent, registration may import relevant data from that organization's member-service system. Imported data must remain attributable to its source and must not silently overwrite participant-provided information without a defined reconciliation rule.

Health, allergy, safeguarding, and emergency-contact data are sensitive. Access must be limited by role and purpose, and the system should record consent, provenance, access, changes, retention, and deletion according to the occasion's policies and legal obligations.

### Closed-loop occasion payments

The occasion may operate as a closed payment system. Participants receive an RFID-enabled wristband that represents or securely references their occasion payment account. Payment processors use an equivalent RFID reader, potentially a smartphone-based reader application, to connect to an occasion-internal payment service and authorize transactions.

The internal payment service should support account balances, transaction authorization, refunds, transfers where allowed, transaction history, limits, settlement, and operational reconciliation without requiring the payment processor to access external payment systems during ordinary occasion transactions.

External payment connectivity is limited to loading participant wristband accounts:

- At externally connected loading stations located at the occasion
- Through a globally accessible web service that allows relatives or other authorized parties to load funds

Loading must identify the intended participant account, record the funding transaction and its source, and make the resulting balance available to the internal occasion payment service. The RFID wristband should not be treated as the sole bearer of value; loss, replacement, or reassignment must be supported by linking the wristband to the participant's occasion payment account.

Payment operations are security-sensitive. Reader access, wristband association, balance changes, refunds, administrative adjustments, and account replacement must be authenticated, authorized, auditable, and resilient to temporary network or service interruptions.

### Occasion operations and support tickets

Occasion management, volunteers, and camp-support personnel operate a ticketing system for participant support and operational issues. A ticket represents a reported need for help, an incident, an observation, or a work item requiring coordination and follow-up.

Tickets may be raised by participants, support personnel, volunteers, management, or integrations. They should support categorization, priority, severity, status, assignment, escalation, communication, attachments, linked contacts or memberships, and a complete activity history.

Tickets should be linked to a camp-site location or other geographic object whenever applicable. Examples include:

- Accidents and first-aid incidents
- Fire, evacuation, and other safety incidents
- Perimeter guarding and access-control needs
- Network and communications failures
- Toilets, water, power, and other utilities
- Access roads and transport routes
- Tents, buildings, containers, and other infrastructure
- General participant support and operational requests

Management requires an always-current operational overview showing open issues, progress, severity, ownership, response times, bottlenecks, and locations requiring help, attention, or inspection. The overview should combine ticket status with the camp map so that issues can be understood geographically and support resources can be dispatched effectively.

The system should distinguish routine service requests from safety-critical incidents. Critical incidents may require immediate escalation, coordinated response teams, restricted visibility, incident command, notifications, and post-incident review. Ticket and incident data must remain auditable, including who reported, acknowledged, assigned, updated, escalated, resolved, and closed the item.

### Closed-loop occasion communications

An occasion with 30,000–40,000 participants will require a closed-loop communication system operating over the occasion network, likely including 5G-based connectivity. The system should provide reliable communication within the occasion while allowing access to different capabilities according to identity, membership, team, role, location, and operational need.

Communication capabilities should include:

- Occasion-wide and targeted alarms or emergency notifications
- Participant-to-participant direct messaging
- Team, group, and operational-unit messaging
- Simple text-like notifications
- Rich, email-like messages with formatted content and attachments
- One-to-many audio or video streaming
- Audio/video conferencing between multiple participants, with n:n conferences capped at approximately 30–50 participants

The communication system should integrate with registration, team structures, the ticketing system, camp locations, and safeguarding rules. For example, an incident may trigger a targeted team notification, while an emergency may require an all-participant alarm. Broadcasts and emergency messages should support acknowledgement, delivery status, escalation, localization, and clear authority to initiate or cancel them.

The platform should distinguish asynchronous messaging, live conferencing, broadcast streaming, and emergency alerting as different communication modes with different delivery, retention, moderation, and reliability requirements. It should support operation during congestion or partial network failure, including prioritization of emergency traffic and appropriate fallback behavior.

### Environmental and food-safety monitoring

The occasion requires monitoring of environmental and operational conditions that affect participant health, safety, compliance, and continuity of operations. Monitoring should combine sensor data, scheduled inspections, manual observations, external data sources, and laboratory or authority reports where applicable.

Areas of interest include:

- Water quality, supply, pressure, temperature, and contamination indicators
- Food handling, storage temperatures, hygiene checks, preparation areas, and inspection findings
- Air pollution and air-quality indicators
- Waste, sanitation, utilities, noise, weather, heat, and other environmental conditions

Monitoring points and observations should be linked to camp-site locations, responsible teams, equipment, suppliers, and applicable thresholds or inspection plans. Measurements should be timestamped and retain their source, unit, calibration or verification information, and data-quality status.

Threshold breaches, missed inspections, anomalous readings, or adverse external conditions may automatically or manually create tickets in the occasion operations system. The resulting ticket should retain the triggering observation, required response, assignment, escalation, corrective action, verification, and closure history.

Environmental monitoring should provide management with current and historical views, trends, maps, compliance status, and unresolved risks. Safety-critical alerts should integrate with the closed-loop communications system according to their severity and authorized response procedures.

### GIS-enabled camp planning and operations

Planning the occasion requires a GIS-enabled camp-site display and design system. It should provide a shared geographic model of the site and support camp modeling, layout design, infrastructure planning, capacity planning, approvals, and publication of operational maps.

The system should model and display geographic features such as camps, teams, buildings, tents, containers, roads, access points, utilities, water points, sanitation, safety zones, gathering points, service areas, monitoring points, and other occasion infrastructure. It should support design alternatives and planning scenarios without making unapproved designs visible as operational truth.

During the occasion, the GIS should provide a real-time operational view with layers for traffic, support tickets, incidents, alarms, environmental observations, infrastructure breakdowns, closures, resources, and other relevant conditions. Tickets and incidents should be created from, located on, and navigable through the map. Map users should be able to filter and aggregate data by severity, status, category, team, time, and geographic area.

The GIS should expose role- and purpose-appropriate views. Detailed operational information may be restricted to management, dispatchers, support teams, or other authorized personnel, while simplified maps can be published to participants. Changes to the geographic model, design, operational status, and published layers should be versioned and auditable.

### Volunteer and occasion workforce management

During planning, pre-camp, the live occasion, and post-camp, volunteer-management personnel need an HR-like system for managing the occasion workforce. The system should support recruitment, candidate intake, screening, interviewing, selection, job or duty assignment, onboarding, active service, satisfaction measurement, offboarding, and overall execution-performance reporting.

Volunteer records should remain linked to the canonical contact, identity, occasion membership, teams, roles, skills, qualifications, availability, preferences, and required safeguarding status. Assignments should describe the duty, location, team, supervisor, shift or time period, required capabilities, and current status. They should integrate with the GIS, ticketing system, communication system, registration process, and authorization model.

The workforce lifecycle should support:

- Workforce plans, job descriptions, staffing targets, and recruitment campaigns
- Applications, screening, interviews, decisions, and candidate communication
- Onboarding tasks, training, briefings, credentials, and access provisioning
- Shift planning, attendance, duty execution, reassignment, and absence handling
- In-job check-ins, satisfaction surveys, wellbeing concerns, feedback, and support tickets
- Offboarding, equipment return, access removal, acknowledgements, and follow-up
- Reporting on staffing, coverage, attendance, satisfaction, delivery, incidents, workload, and operational performance

Performance reporting should support both aggregate operational improvement and appropriate individual follow-up. Sensitive personnel, safeguarding, wellbeing, interview, and performance information must be purpose-limited and access-controlled.

### Fundraising and sponsor management

The occasion will require a fundraising organization and a system for attracting, maintaining, and developing sponsors. Sponsor management should support the full relationship lifecycle from prospect identification and qualification through proposals, negotiation, agreement, delivery, renewal, and long-term development.

The system should maintain sponsor organizations and their contacts, relationship owners, interests, sector restrictions, sponsorship history, commitments, agreements, payment status, activation plans, delivered benefits, issues, feedback, and renewal opportunities. It should support sponsorship packages and individually negotiated arrangements, including financial contributions, in-kind contributions, services, equipment, venues, media, and volunteer support.

Sponsor commitments should be connected to the operational systems responsible for delivery. Examples include branding and communication placements, occasion activities, access or hospitality, equipment and stock, GIS locations, tickets or memberships, invoices, and sponsor reporting. The system should provide fundraising forecasts, pipeline views, commitment tracking, benefit fulfillment, relationship health, and post-occasion value reporting.

Sponsor data, agreements, financial information, and partner contacts require controlled access, clear ownership, audit history, and separation between prospective, active, fulfilled, disputed, and expired commitments.

### Arrival and departure logistics

Arrival and departure are critical operational windows that strongly influence the success of the occasion. The system must coordinate the movement of participants, volunteers, staff, suppliers, equipment, and other goods to and from the camp site, particularly on arrival and departure days when demand and congestion will be extreme.

An arrival/departure logistics system should support transport declarations, scheduled time slots, capacities, routes, access gates, staging areas, unloading and loading points, vehicle and driver information, group manifests, accessibility needs, and real-time operational status. It should coordinate what is expected, where it should go, when it should arrive or leave, and which team is responsible for receiving, directing, loading, unloading, or resolving exceptions.

The system must interface with:

- Participant registration, to understand people, groups, arrival/departure details, needs, and permissions
- The GIS camp-design system, to plan routes, gates, staging areas, traffic flows, closures, and destination locations
- Stock management, to coordinate equipment and goods being delivered, issued, loaded, returned, or dispatched
- The ticketing system, to report and coordinate delays, incidents, missing goods, access problems, breakdowns, and other exceptions

It should provide operational dashboards for traffic control, reception, camp teams, stock personnel, transport coordinators, and management. Planned movements should be compared with actual arrivals, departures, loading, unloading, and throughput so that bottlenecks can be detected and routes or allocations adjusted during the occasion.

The system should support both individual and group movement, including buses, private vehicles, supplier deliveries, waste collection, emergency access, and other operational transport. Arrival and departure plans should be versioned, communicated to relevant parties, and auditable after the occasion.

### Supply-chain management

The occasion requires a supply-chain management system to plan and execute the material, consumable, equipment, and asset flows required to build, operate, maintain, and dismantle the camp. It should cover demand planning, specifications, sourcing, procurement, supplier coordination, order fulfillment, deliveries, staging, consumption, replenishment, returns, and post-occasion disposition.

Supply-chain planning should be driven by camp designs, infrastructure plans, work packages, maintenance schedules, participant capacity, operational forecasts, and asset availability. It should support bills of materials, material requirements, substitutions, lead times, minimum stock levels, reservations, delivery milestones, quality checks, and cost or funding constraints.

The system should interface with:

- Fundraising and sponsor management, to identify sponsor-preferred procurement inquiries, sponsored goods or services, contribution restrictions, approvals, and attribution
- Stock management, to maintain optimal stock levels, reserve existing assets, avoid unnecessary purchases, and coordinate issuing, returns, maintenance, and replenishment
- Arrival and departure logistics, to schedule supplier deliveries, transport materials, manage gates and staging areas, and coordinate loading and unloading
- GIS camp planning, to connect requirements and deliveries to construction zones, facilities, storage locations, and operational areas
- Ticketing and workforce management, to create or follow up on supply issues, work packages, shortages, breakdowns, and responsible teams

The SCM system should provide management with current views of demand, committed supply, stock coverage, procurement status, delivery risk, shortages, costs, supplier performance, and readiness for construction, operation, and breakdown. Material and purchasing decisions should remain traceable from requirement through supplier commitment, delivery, use, return, disposal, or post-occasion stock.

### Facilities and utilities management

Building out the camp from its approved design requires a facilities and utilities management system. It should manage the lifecycle of facilities, infrastructure, and utility services from acquisition and delivery through installation, commissioning, operations, maintenance, breakdown response, dismantling, return, refurbishment, or disposal.

The system should cover facilities and services such as tents, buildings, containers, roads, access points, power, water, sanitation, waste, network infrastructure, lighting, heating or cooling, and other temporary or permanent camp infrastructure. Each facility or utility installation should be associated with its GIS location, design version, responsible team, supplier, stock or asset records, operating status, capacity, inspection schedule, maintenance history, and decommissioning plan.

Facilities and utilities personnel should be able to plan work packages, installation tasks, inspections, preventive maintenance, corrective maintenance, service outages, safety checks, and breakdown response. Failures and service requests should integrate with the ticketing system, while environmental readings, utility measurements, and food-safety observations should be able to trigger maintenance or compliance work.

The system should coordinate with supply-chain management for acquisition and replenishment, stock management for asset issue and return, GIS for location and network context, arrival/departure logistics for delivery and removal, workforce management for assignments, and communications for outages, hazards, and planned works.

At breakdown, facilities and utility assets should be inspected, disconnected or made safe, removed, returned to stock or suppliers where applicable, and reconciled against their original acquisition, installation, maintenance, and operational records.

### Security, access control, and threat prevention

The occasion requires a dedicated security system for camp-site monitoring, access control, credential management, restricted zones, visitor control, lost wristbands, and security incidents. It should support preventive security and counter-terrorism operations while respecting participant safety, privacy, and lawful use of security data.

The system should manage credentials and access rights for participants, volunteers, staff, suppliers, contractors, visitors, vehicles, and emergency services. Access should be based on identity, membership, role, assignment, time, location, and operational purpose. Restricted zones, gates, checkpoints, access conditions, escort requirements, and temporary permissions should be modeled in the GIS and enforced through appropriate readers, gates, or guard procedures.

Camp-site monitoring may include guard observations, access events, alarms, cameras or other sensors where approved, perimeter checks, suspicious-activity reports, lost or stolen wristband reports, and visitor registrations. A lost wristband must be revocable promptly and replaceable without losing the participant's payment account or occasion identity.

Security incidents should integrate with the ticketing and incident-command systems, GIS locations, closed-loop communications, registration and safeguarding workflows, and emergency services or government bodies where required. Sensitive security information should be restricted by role and need-to-know, with complete audit history for credential issuance, access decisions, overrides, alerts, incidents, and evidence handling.

### Calendar, scheduling, and capacity management

Time is a fundamental organizing concept for the occasion. A calendar-based planning system should coordinate shifts, venues, vehicles, equipment, teams, appointments, training, deliveries, maintenance, inspections, meetings, and other operational activities.

The system should support shared calendars, recurring activities, time zones where relevant, dependencies, buffers, preparation and teardown periods, assignment of people and teams, resource bookings, location constraints, capacity limits, waitlists, conflicts, approvals, cancellations, substitutions, and real-time changes. It should distinguish planned, confirmed, active, completed, cancelled, and missed activities.

Scheduling should account for the availability, qualifications, workload, rest requirements, and access rights of personnel, as well as the capacity and condition of venues, vehicles, equipment, infrastructure, and communication resources. It should identify conflicts and under-capacity conditions before they affect operations.

The calendar must interface with workforce management for shifts and training, GIS for venues and locations, stock and facilities management for equipment and infrastructure, SCM and arrival/departure logistics for deliveries, ticketing for operational work, and communications for reminders, changes, alerts, and acknowledgements. Management should receive capacity, coverage, utilization, lateness, cancellation, and execution-performance views.

### Performance, learning, and knowledge management

Every system in the occasion platform should produce operational performance data. This includes response times, throughput, correctness, errors, retries, exceptions, changes, user feedback, resource utilization, outcomes, and the quality of inputs and results. The data should feed a shared knowledge system that supports real-time operations, continuous improvement, planning for future occasions, and post-occasion learning.

AI may assist in evaluating the quality of user input and system results, identifying patterns, and generating recommendations. Examples include detecting recurring events, analyzing accidents, identifying repeated or similar material orders, forecasting stock requirements, recognizing bottlenecks, evaluating support responses, and highlighting unexpected capacity or safety conditions. AI-generated evaluations and recommendations should remain distinguishable from observed facts and human decisions.

The knowledge system should provide real-time dashboards and operational views for KPIs, forecasts, capacity, response times, satisfaction, safety, financial performance, stock, supply-chain readiness, workforce coverage, communications delivery, and incident trends. It should also support historical comparisons between planning assumptions and actual execution, including lessons learned that can be reused for later occasions.

Performance data must retain its source, time, tenant and occasion, context, definition, and confidence or quality status. The platform should support consistent metric definitions, cross-system correlation, data quality monitoring, explainable analysis, controlled access, and correction of erroneous data.

### Document, knowledge, and procedure management

Most occasion systems should integrate with a shared document, knowledge, and procedure management system. It should provide a trusted home for runbooks, safety procedures, maps, forms, policies, training material, technical documentation, checklists, templates, and other versioned operational guidance.

Documents and knowledge items should be associated with their owning organization or team, relevant occasion, facility, location, asset, ticket category, role, training activity, or operational procedure. The system should support authoring, review, approval, publication, versioning, effective dates, expiry, supersession, translations, acknowledgements, search, controlled distribution, and offline access where required.

Operational systems should be able to link directly to the applicable guidance from screens and workflows. For example, a ticket category can reference a response runbook, a facility can reference maintenance procedures, a safeguarding workflow can reference policies and forms, and a GIS location can expose current maps or emergency instructions. Links should resolve to the correct approved version for the occasion and user's role.

The system should distinguish draft, reviewed, approved, published, expired, withdrawn, and archived material. Critical guidance should require ownership, review responsibility, change history, acknowledgement tracking, and confirmation that field personnel have access to the current applicable version.

### Financial and economic planning and execution

Financial and economic planning must be tightly integrated with occasion planning and scheduling, supply-chain management, CRM and sponsor management, stock and asset management, workforce management, registrations, payments, and facilities operations. The system should connect operational commitments and actual execution to budgets, forecasts, funding sources, cost centers, projects, work packages, and financial outcomes.

It should support invoices for participant or customer charges, missing or damaged assets, supplier invoices, sponsor commitments, services, rentals, and other obligations. It should also support payroll-like settlements for volunteer expenses, contractors, suppliers, allowances, reimbursements, and other occasion workforce or partner arrangements where applicable.

Financial operations should include planning and budgeting, purchase commitments, approvals, accounts payable and receivable, payment status, reconciliation, settlements, credits, refunds, write-offs, cost allocation, cash and closed-loop payment reconciliation, and audit trails. Operational systems should be able to create or update financial obligations without duplicating the authoritative accounting record.

Management should receive current and historical views of budget versus actuals, committed versus realized costs, revenue, sponsor funding, procurement exposure, stock value, asset losses, supplier performance, workforce costs, cash position, forecast variance, and occasion-level economic performance. Every financial result should be traceable back to its source event, order, asset, agreement, assignment, invoice, payment, or approval.

### Occasions and activities management

The occasion requires a system for designing, planning, operating, and reporting on occasions and activities offered during the camp period. Participants should be able to discover and sign up for activities during their stay, subject to eligibility, capacity, timing, location, safeguarding, and other operational constraints.

Activity definitions should describe purpose, audience, schedule, venue, capacity, prerequisites, staffing, equipment, materials, suppliers, cost, sponsor involvement, safety requirements, registration rules, and communication needs. The system should support proposals, review and approval, publication, participant registration, waitlists, cancellations, attendance, feedback, incident linkage, and post-activity reporting.

Management should be able to monitor demand, sign-ups, attendance, satisfaction, staffing, resource consumption, cost, revenue, safety, and operational performance. This should support right-sizing offerings—such as adding capacity, combining or cancelling under-subscribed activities, changing venues, or reallocating staff and materials.

During the camp period, activity execution should be prioritized and coordinated with workforce management, financial planning, stock and asset management, SCM, GIS, scheduling, communications, ticketing, and safeguarding. Other systems should be able to use activity demand and execution plans to prioritize people, supplies, equipment, venues, transport, support coverage, and financial commitments.

### CRM and relationship management

The occasion requires a CRM capability for managing relationships with participants, families, scout organizations, suppliers, sponsors, contractors, authorities, partners, and other stakeholders. It should provide a shared view of contacts, organizations, relationship owners, interactions, commitments, communication history, requests, opportunities, and follow-up actions.

CRM records should use the canonical contact and organization model, while preserving occasion and relationship context. The system should support segmentation, consent-aware communication, campaigns, tasks, notes, cases, service history, relationship health, and handover between responsible personnel. Sponsor management, supplier management, participant support, fundraising, and external coordination should be able to use the same relationship history without duplicating contacts.

### Emergency and incident command

Safety-critical events require an incident-command capability in addition to ordinary ticketing. It should support incident declaration, classification, command roles, response plans, objectives, operational periods, situation reports, resource requests, decisions, briefings, handovers, escalation, and controlled closure.

Incident command should coordinate management, security, medical, fire, logistics, communications, facilities, safeguarding, government bodies, police, and emergency services as appropriate. It should use the GIS for situational awareness, the ticketing system for work items, closed-loop communications for alerts and instructions, scheduling for response resources, and the knowledge system for approved response procedures. Sensitive incidents must support restricted access, evidence handling, audit history, and post-incident review.

### Transport and traffic management

Beyond arrival and departure logistics, the occasion requires ongoing transport and traffic management for private vehicles, buses, shuttles, deliveries, waste collection, service vehicles, emergency access, parking, pedestrian flows, and route closures.

The system should maintain routes, gates, parking and staging areas, vehicle permits, transport capacity, dispatches, schedules, traffic observations, congestion, incidents, closures, and live operational status. It should connect with the GIS, arrival/departure logistics, SCM, facilities, security, ticketing, scheduling, and communications systems. Management should be able to optimize throughput, prioritize emergency and essential movements, and publish relevant instructions to participants and operators.

### Food-service and catering management

The occasion requires a food-service and catering system for planning and delivering meals and refreshments at camp scale. It should support menus, recipes, dietary and allergy requirements, meal forecasts, production plans, kitchens, serving points, suppliers, food inventory, equipment, staffing, meal schedules, capacity, waste, and distribution.

Food-service planning should use registration data and activity or attendance forecasts while limiting access to sensitive dietary and allergy information. The system should coordinate procurement and deliveries with SCM, inventory with stock management, kitchen and facility needs with facilities management, staffing with workforce management, locations with GIS, payments or charges with financial systems, and hygiene or temperature controls with environmental and food-safety monitoring.

It should report planned versus served meals, shortages, surplus, waste, cost, supplier performance, dietary fulfillment, incidents, and food-safety compliance.

### Data integration and occasion-platform services

The occasion systems require shared platform services for APIs, event-driven integration, imports, synchronization, master data, search, workflow, notifications, audit trails, reporting feeds, offline operation, and controlled data exchange with external organizations.

The platform should establish authoritative ownership for common data such as contacts, identities, memberships, teams, locations, assets, suppliers, activities, tickets, financial obligations, and documents. Integrations must preserve identifiers, provenance, consent, tenant scope, version, timestamps, retries, errors, reconciliation status, and audit history. External integrations should be isolated through controlled interfaces and must not bypass authorization, safeguarding, financial controls, or data-retention rules.

Shared services should support reliable synchronization during connectivity loss, idempotent processing, dead-letter or exception handling, operational observability, schema/version management, access control, and data-quality monitoring.

## Core identity concepts

### Tenant

A **tenant** is the administrative and data-isolation workspace created by an individual or organizational identity. It can contain multiple occasions: for example, an organizer's tenant may contain both `SL2026` and `SL2030`. A tenant is not an occasion or automatically identical to an organization contact.

After signup, an authenticated identity creates a tenant and atomically becomes its first `tenant_admin`, with tenant-wide administration roles and permissions. A represented organizational identity may create the tenant through an authorized real-user operator, retaining attribution to both. Tenant admins may grant `tenant_admin` to additional identities, create occasions, open them for recruitment, and assign `occasion_admin` within each occasion.

### Occasion

An **occasion** is an organized camp or other bounded undertaking within exactly one tenant. Every occasion data point and domain event has the context **tenant > occasion > event**, represented by `tenant_id`, `occasion_id`, and `event_id` where relevant. Tenant-wide administration and global signup facts exist outside any occasion and must be explicitly scoped, not assigned a fictitious occasion.

Tenant administration grants authority across that tenant, including its occasions; `occasion_admin` is restricted to its assigned occasion. Administrative powers do not automatically erase purpose-specific restrictions on health, safeguarding or financial decisions. Platform administration is separate from both. Opening recruitment is an explicit governed occasion transition, distinct from opening participant registration or approving applicants.

### Contact

A **contact** is the primary real-world party known to the organization. A contact may be a physical human, a mechanical/electronic alter ego (such as an agent, device or service acting as a party), or an organization and may participate in several contexts, including:

- Supplier
- Volunteer
- Camper or participant
- Customer, sponsor, purchaser, or ticket holder
- Staff member or other occasion stakeholder

The contact is the shared reference for relationships, communication, transactions, participation, and operational records. A single person should not need separate records merely because they have more than one relationship with the jamboree.

### Contact types

**Contact types** are administrator-defined tags used to annotate contacts. Administrators may create any number of types, such as `branch`, `business`, `union`, or `club`, and may assign multiple types to the same contact.

Contact types are descriptive and extensible rather than a fixed subtype hierarchy. They allow the organization to identify and filter different kinds of contacts without requiring a schema change or creating duplicate contacts. A contact's types do not by themselves determine its roles, memberships, or permissions.

### Identity

An **identity** is the stable digital principal linked to a contact. Every human contact and every mechanical/electronic alter-ego contact has exactly one identity. An organizational contact may have one identity or no identity; each identity belongs to exactly one contact. Identity existence is distinct from interactive sign-in capability: a child has an identity even when access is guardian-mediated.

An organizational identity may be used by multiple authorized real users. Each user authenticates with their own human identity and receives an explicit, scoped delegation to act through the organizational identity. The organization remains the represented principal while the actual operator remains attributable. An organization without an identity can still be referenced in relationships, contracts and operational records, but cannot authenticate or hold an identity-based membership in its own right.

An identity has an immutable internal identifier and may support one or more authentication methods. Authentication establishes who the user is; it does not, by itself, determine what that user is allowed to do. One identity may have memberships in multiple tenant contexts.

Verified email and phone login identifiers belong to the identity, not to each membership. A member may add, edit, replace or retire an identity only through a controlled workflow. Human and mechanical/electronic contacts must retain their required identity; organizational contacts may acquire or relinquish their optional identity through a governed workflow that resolves delegations, memberships and outstanding obligations.

A second identifier serving the same goal as email address is **cell-phone number**, being equivally unique to the email address.

Human self-service sign-in uses verified email, phone, or both; enrollment and identifier changes require verification. An identity without enabled human sign-in still exists. Mechanical/electronic identities use approved machine credentials or trusted federation bindings; organizational identities can be accessed through authenticated human delegation without inventing a shared personal email or phone login.

Changing their email address/cell-phone number require the member to perform the validation process again.

Identities are also required to update their profile if they change their identifier (email address / cell-phone number).

### Membership

A **membership** represents an identity's participation in an occasion within its owning tenant. Tenant administration/access is recorded separately as `TenantAccess` and scoped grants; it does not require an occasion membership. Examples may include participant registration, volunteer affiliation, supplier affiliation, or membership of a team, group, or organization.

Memberships should be modeled independently from identity so that a person can retain one authenticated identity while having distinct memberships across occasions, including several occasions within one tenant, and changing relationships over time.

An identity has **at most one occasion membership per occasion**. That membership may carry multiple roles, team affiliations, and assignments. Role contexts distinguish capacities such as participant and volunteer within the same membership; they do not create additional memberships.

For example, LISA has one membership in `SL2026` and a separate membership in `SL2030`, both linked to the same identity. Her participant and hospitality volunteer roles at `SL2026` share its single membership. Enforce uniqueness of `(tenant_id, occasion_id, identity_id)` and preserve that membership's identity through role changes or reactivation.

Accepting a membership includes setting the data persistence time window. Identities may opt-in to allowing their data being persisted outside the time frame of the membership (an occasion by default).

### Contact hierarchy

Contacts are organized in a tree-like hierarchy. A person contact may be a child of another person contact, representing a management or supervisory relationship. A person may ultimately belong under an organization contact, and organizations may themselves be children of other organizations, representing structures such as enterprise branches within a corporation.

The hierarchy should support people and organizations as contact categories while preserving the contact as one extensible entity. The exact relationship semantics (for example, manager, branch, subsidiary, or department) may be represented by a relationship type rather than inferred solely from a contact tag or tree position.

### Membership and team hierarchy

Memberships are organized through teams. Teams form their own tree-like hierarchy, with occasion-specific labels such as patrol, troop, group, division, more. A team may be a child of another team, allowing the occasion to model nested operational and participant structures.

A membership may belong to one or more teams according to the occasion's rules. Team membership can provide inherited roles or permissions, while direct assignments remain possible.

### Role and authorization

A **role** is a named set of permissions. Roles may be assigned individually or as sets to memberships, teams, contacts, or other supported assignment targets. Assignments may be direct or inherited through the relevant hierarchy.

A **permission** is an allowed operation or capability. Permissions may likewise be assigned individually or as sets to roles, memberships, teams, contacts, or other supported assignment targets. The effective authorization of an identity is the result of evaluating applicable assignments across its contact, memberships, teams, roles, and scopes.

One example is the **team manager/lead** role. Within its authorized team scope, this role may assign memberships to teams and assign roles or permissions to memberships and teams. This is delegated administration: the authority must be limited to the relevant team hierarchy and must be auditable.

Authorization should answer questions such as:

- Which resources may this user view or change?
- In which organizational or occasion context do those permissions apply?
- Does the permission apply to all records or only to an assigned scope?
- Is the permission temporary or valid only during a particular occasion phase?

The model should therefore support multiple roles for the same identity, across tenants and within occasion membership or role contexts, rather than treating authorization as a single global user type. It must also support both role-based and direct permission assignments.

## Relationship overview

```text
Human/MechanicalElectronicContact 1 ─── 1 Identity
OrganizationContact 1 ─── 0..1 Identity
HumanIdentity 0..* ─── 0..* OrganizationIdentity (scoped IdentityUseDelegation)
Contact 0..1 ─── 0..* Contact (parent-child hierarchy)
Identity 1 ─── 0..* Membership
Tenant 1 ─── 0..* Occasion
Tenant 1 ─── 0..* TenantAccess
Identity 1 ─── 0..* TenantAccess
Occasion 1 ─── 0..* Membership
Membership 0..1 ─── RoleContext
Membership 0..* ─── 0..* Team
Team 0..1 ─── 0..* Team
Role 0..* ─── 0..* Permission
Contact, Membership, Team ─── Role assignments
Contact, Membership, Team, Role ─── Permission assignments
AssetDefinition 1 ─── 0..* AssetUnit or StockItem
Membership/Contact 1 ─── 0..* AssetOrder
AssetOrder 1 ─── 1 BillOfMaterials
AssetOrder ─── PickList ─── StockIssue
StockIssue ─── ReturnInspection ─── StockDisposition
StockDisposition ─── 0..1 Invoice
Contact/Membership 1 ─── 0..1 Registration
Registration 1 ─── 0..* RegistrationAnswer
Registration ─── 0..* ConsentRecord
Registration ─── 0..1 SafeguardingEvaluation
Registration ─── 0..* ImportedMemberData
Registration/Membership 1 ─── 0..1 OccasionPaymentAccount
OccasionPaymentAccount 1 ─── 0..1 RFIDWristband
RFIDReaderApp ─── OccasionPaymentService
OccasionPaymentAccount ─── 0..* PaymentTransaction
ExternalLoadingStation/WebTopUpService ─── OccasionPaymentAccount
Contact/Membership ─── 0..* SupportTicket
SupportTicket ─── 0..1 CampSiteLocation
SupportTicket ─── 0..* TicketActivity
SupportTicket ─── 0..* Assignment/Escalation
ManagementOverview ─── SupportTicket and CampSiteLocation
Contact/Membership ─── 0..* ConversationParticipant
Conversation ─── 0..* Message
Team ─── 0..* Conversation
Incident ─── 0..* Communication
Communication ─── 0..* DeliveryReceipt/Acknowledgement
Communication ─── 0..1 LiveSession
MonitoringPoint ─── 0..* Measurement/Inspection
Measurement/Inspection ─── 0..* ThresholdRule
Measurement/Inspection ─── 0..* SupportTicket
MonitoringPoint ─── 0..1 CampSiteLocation
ThresholdBreach ─── 0..* Communication
CampSite ─── 0..* GeographicFeature
CampDesign ─── 0..* GeographicFeature
GeographicFeature ─── 0..* MapLayer
MapLayer ─── 0..* SupportTicket/Incident/Measurement
CampDesign ─── 0..* DesignVersion
Contact/Membership 1 ─── 0..* VolunteerApplication
VolunteerApplication ─── 0..* Interview
Membership 1 ─── 0..* WorkforceAssignment
WorkforceAssignment ─── 0..* Shift/Availability
WorkforceAssignment ─── 0..* OnboardingTask
WorkforceAssignment ─── 0..* SatisfactionResponse
WorkforceAssignment ─── 0..1 OffboardingRecord
WorkforceAssignment ─── 0..* PerformanceRecord
Contact/Organization ─── 0..* SponsorshipOpportunity
SponsorshipOpportunity ─── 0..1 SponsorshipAgreement
SponsorshipAgreement ─── 0..* SponsorCommitment
SponsorCommitment ─── 0..* SponsorBenefit
SponsorBenefit ─── 0..* BenefitDelivery
SponsorCommitment ─── 0..* Invoice/Payment
Contact/Membership/Team ─── 0..* TransportPlan
TransportPlan ─── 0..* ArrivalDepartureSlot
ArrivalDepartureSlot ─── 0..* Person/Vehicle/GoodsManifest
ArrivalDepartureSlot ─── 0..1 CampSiteLocation
TransportPlan ─── 0..* SupportTicket
GoodsManifest ─── 0..* AssetOrder/StockMovement
CampDesign/WorkPackage ─── 0..* SupplyRequirement
SupplyRequirement ─── 0..* BillOfMaterial/MaterialNeed
MaterialNeed ─── 0..* ProcurementRequest
ProcurementRequest ─── 0..1 PurchaseOrder
PurchaseOrder ─── 0..* Delivery
Delivery ─── 0..* StockMovement
SupplyRequirement ─── 0..* SponsorCommitment
Facility/UtilityInstallation ─── 0..1 GeographicFeature
Facility/UtilityInstallation ─── 0..* MaintenanceWorkOrder
Facility/UtilityInstallation ─── 0..* Inspection
Facility/UtilityInstallation ─── 0..* SupportTicket
Facility/UtilityInstallation ─── 0..* UtilityReading
Facility/UtilityInstallation ─── 0..1 StockItem/AssetUnit
MaintenanceWorkOrder ─── 0..* WorkforceAssignment
Contact/Membership ─── 0..* Credential
Credential ─── 0..* AccessGrant
AccessGrant ─── 0..1 RestrictedZone
Credential ─── 0..* AccessEvent
Visitor ─── 0..* VisitorAccess
SecurityObservation ─── 0..* SupportTicket/Incident
SecurityIncident ─── 0..* Communication
SecurityIncident ─── 0..1 CampSiteLocation
Calendar ─── 0..* ScheduledActivity
ScheduledActivity ─── 0..* Person/Team/ResourceAssignment
ScheduledActivity ─── 0..1 CampSiteLocation
ScheduledActivity ─── 0..* CapacityConstraint
ScheduledActivity ─── 0..* Communication
ScheduledActivity ─── 0..* SupportTicket
SystemEvent ─── PerformanceMeasure
PerformanceMeasure ─── 0..* KPI/Forecast/Insight
UserInput/SystemResult ─── 0..* QualityEvaluation
QualityEvaluation ─── 0..* KnowledgeItem
KnowledgeItem ─── 0..* Recommendation/LessonLearned
KnowledgeItem ─── 0..* DocumentVersion
KnowledgeItem ─── 0..* Procedure/Runbook/Form/Policy
OperationalSystem ─── 0..* KnowledgeLink
KnowledgeLink ─── 0..1 ApprovedDocumentVersion
Role/Team/WorkforceAssignment ─── 0..* KnowledgeItem
OperationalSystem ─── 0..* FinancialTransaction/Obligation
Planning/Scheduling/SCM/CRM/Stock ─── FinancialPlanningExecution
FinancialPlanningExecution ─── 0..* Invoice
FinancialPlanningExecution ─── 0..* Settlement
FinancialPlanningExecution ─── 0..* Budget/Forecast
FinancialTransaction/Obligation ─── 0..* AuditEntry
ActivityDefinition ─── 0..* ActivityOffering
ActivityOffering ─── 0..* ActivityRegistration
ActivityOffering ─── 0..* WorkforceAssignment
ActivityOffering ─── 0..* AssetOrder/StockRequirement
ActivityOffering ─── 0..* SupplyRequirement
ActivityOffering ─── 0..1 CampSiteLocation
ActivityOffering ─── 0..* ActivityOutcome/Feedback
Contact/Organization ─── 0..* CRMInteraction/CRMCase
CRMCase ─── 0..* SupportTicket
Incident ─── 0..1 IncidentCommand
IncidentCommand ─── 0..* CommandRole/OperationalPeriod/ResourceRequest
Vehicle/TransportUnit ─── 0..* TransportMovement
TransportMovement ─── 0..1 Route/Gate/ParkingArea
TransportMovement ─── 0..* TrafficObservation
MealPlan ─── 0..* MealOffering
MealOffering ─── 0..* MealRegistration/MealService
MealOffering ─── 0..* FoodProductionPlan
FoodProductionPlan ─── 0..* FoodSafetyCheck
OperationalSystem ─── 0..* IntegrationEvent
IntegrationEvent ─── 0..1 ReconciliationRecord
MasterDataEntity ─── 0..* ExternalReference
Identity ─── authenticates by verified human login identifiers, machine credentials, or delegated organizational access
Role ─── grants permissions within a defined scope
```

The important invariants are:

- Authentication establishes a stable identity; email/phone are verified human login identifiers, while machines use approved credentials and organizational access can be delegated.
- Each human or mechanical/electronic contact has exactly one identity; an organizational contact has zero or one identity. Each identity belongs to exactly one contact. Multiple authenticated humans may use an organizational identity through explicit delegation.
- Active verified human email/phone login identifiers are globally unique; organization contact email fields are not automatically login identifiers.
- Identity changes are controlled and preserve required human/mechanical/electronic identities; organizational identities are optional and their removal resolves dependent access and memberships.
- A tenant contains zero or more occasions; each occasion belongs to exactly one tenant. Administration scopes distinguish tenant-wide and occasion-specific authority.
- An identity may have memberships in multiple tenants.
- Membership is the occasion-scoped participation relationship; TenantAccess represents tenant-level access without requiring recruitment or occasion participation.
- A role context is optional and does not necessarily have a one-to-one relationship with membership.
- Each identity has at most one membership in each occasion, unique on `(tenant_id, occasion_id, identity_id)`; all participant/volunteer roles and team affiliations in that occasion refer to it.
- Contacts and teams are hierarchical structures with parent-child relationships.
- Roles and permissions may be assigned directly or as sets to contacts, memberships, teams, and roles as supported by the authorization model.
- Authorized team managers/leads may administer team membership and delegated roles/permissions within their permitted team scope.
- Asset orders, issues, returns, inspections, stock dispositions, and invoices must remain traceable to the responsible contact or membership.
- Occasion participation is established through registration, not merely through authentication or a general contact record.
- Imported member-service data must retain source provenance and follow an explicit consent and reconciliation process.
- Sensitive registration and safeguarding data must be purpose-limited, access-controlled, auditable, and subject to defined retention rules.
- Ordinary occasion purchases use the occasion-internal payment service and do not depend on external payment-system access.
- External payment connectivity is restricted to authorized account-loading channels.
- Wristbands identify or reference payment accounts but are replaceable credentials, not the sole durable store of value.
- Operational tickets and incidents must remain linked to their location, responsible personnel, response activity, and resolution history.
- Safety-critical incidents require stricter access, escalation, and audit handling than routine support requests.
- Communication must be scoped and authorized by identity, membership, team, role, location, and emergency authority as appropriate.
- Emergency communications must be prioritized, auditable, and distinguishable from ordinary messages.
- Environmental observations and alerts must retain source, time, location, data quality, response, and resolution history.
- Environmental and food-safety threshold breaches must be able to create or update operational support tickets.
- The GIS is the shared geographic context for planning, operational tickets, incidents, environmental observations, traffic, alarms, and infrastructure status.
- Planned, approved, and live geographic states must be distinguishable and auditable.
- Workforce assignments must remain linked to the responsible membership, team, role, location, time period, and supervisor where applicable.
- Volunteer lifecycle and performance data must be purpose-limited, access-controlled, and auditable.
- Sponsor commitments and benefits must remain traceable from agreement through operational delivery, invoicing, fulfillment, and reporting.
- Sponsor and fundraising information must be access-controlled and auditable, with clear ownership of each relationship.
- Arrival and departure movements must remain traceable to their people or goods, time slot, route, location, responsible team, and actual operational outcome.
- Planned and actual movement data must be distinguishable so that delays, exceptions, and throughput can be analyzed.
- Supply requirements must remain traceable from camp or work-package demand through procurement, delivery, stock, consumption, return, or disposal.
- Sponsor-preferred procurement and sponsored contributions must be visible in supply planning without bypassing procurement controls.
- Facilities and utility installations must remain traceable from acquisition and design through installation, operation, maintenance, breakdown, and return or disposal.
- Utility outages, facility failures, and safety findings must be able to create or update support tickets and trigger authorized communications.
- Credentials and access grants must be time-, location-, role-, and purpose-scoped where required, revocable, and auditable.
- Lost or stolen wristbands must be revocable and replaceable without losing the associated payment account or participant identity.
- Security observations and incidents must be protected by need-to-know access and linked to their location, response, and evidence history.
- Scheduled activities must remain traceable to their time, location, assigned people or teams, resources, capacity constraints, changes, and execution outcome.
- The scheduling system must identify relevant conflicts, over-allocation, missing qualifications, and insufficient operational capacity.
- Operational systems must emit consistent, traceable performance and outcome data for cross-system analysis.
- AI-generated evaluations, insights, and recommendations must be identifiable, explainable where practical, and subject to appropriate human oversight.
- Observed facts, derived measures, AI assessments, recommendations, and human decisions must remain distinguishable.
- Operational guidance must be versioned, approved, occasion-scoped where necessary, and discoverable from the workflows and systems that depend on it.
- Users must be able to identify the currently effective guidance and distinguish it from drafts, superseded, expired, or withdrawn material.
- Financial obligations and results must remain traceable from operational source through approval, invoice, payment or settlement, reconciliation, reporting, and audit.
- Financially relevant systems must integrate with an authoritative financial record rather than creating conflicting independent ledgers.
- Activity demand, commitments, execution, and outcomes must remain traceable across participant registrations, workforce, resources, supply, financial records, and reporting.
- Published activity offerings must reflect current capacity, staffing, safety, location, and registration status.
- CRM interactions and cases must reference canonical contacts and preserve consent, ownership, occasion context, and communication history.
- Critical incidents must be managed through explicit command roles, response objectives, resource assignments, decisions, handovers, and post-incident review.
- Transport movements must remain traceable to their vehicle or group, route, time, destination, permit, operational status, and responsible party.
- Food-service plans must account for demand, capacity, dietary and allergy requirements, supply, staffing, hygiene, waste, and financial impact.
- Integrations must preserve source provenance, tenant scope, identifiers, version, delivery status, errors, reconciliation, and audit history.

## Initial domain principles

1. **One real-world party, one canonical contact.** Avoid duplicate contacts for different operational contexts.
2. **Authentication is separate from authorization.** Logging in does not imply a fixed role.
3. **One identity may have multiple roles and memberships.** The user context must be resolved from the requested operation, tenant, occasion where applicable, membership, and optional role context.
4. **Relationships can change over time.** Memberships and permissions should be capable of having status and validity periods.
5. **One membership per identity per occasion.** Optional role contexts distinguish capacities within that single occasion membership.
6. **Tenant and occasion scopes are distinct.** One tenant may own multiple occasions; identities may have separate memberships in those occasions, while tenant-wide administration uses TenantAccess and grants.
7. **Organizations matter.** Suppliers, scout groups, teams, and other bodies may need their own contact records and relationships to people.
8. **Operational systems should reference contacts consistently.** Orders, tickets, support cases, volunteer assignments, and supplier records should link back to the canonical contact where appropriate.

## Remaining open questions

### Identity lifecycle

- How are globally unique email-address changes verified and finalized?
- How is the controlled identity replacement workflow approved, audited, and recovered if interrupted?

### Contacts and organization structure

- Which relationship types are required in the contact hierarchy, such as manager, branch, subsidiary, or department?
- Who may create, rename, archive, or retire administrator-defined contact types?
- Are contact types tenant-specific, shared across occasions, or both?
- What happens to existing contacts and filters when a contact type is renamed or retired?

### Memberships and teams

- Can memberships belong to multiple teams, and how are conflicting team assignments resolved?
- Which relationship types or labels are required for team hierarchies beyond labels such as patrol, troop, group, and division?
- How is membership and role inheritance handled across parent and child teams?

### Roles, permissions, and delegated administration

- How should permissions be scoped to teams, team hierarchies, camps, suppliers, geographical areas, or other units?
- What exact scope may a team manager/lead administer: one team, descendants, or another defined boundary?
- Which roles and permissions may a team manager/lead assign, and how is privilege escalation prevented?
- How are conflicting grants, explicit denials, and removal of inherited permissions resolved?
- Who may create or modify the role and permission catalog?

### Audit and integration

- Which records require historical and auditable changes to roles, permissions, memberships, teams, contact data, and identity data?
- What is the system of record for registration, payments, support, and map data?

### Stock and asset management

- Which asset categories require individual-unit tracking, serial numbers, condition history, or maintenance history?
- Are asset orders placed by individuals, teams, or both, and who may approve or modify them?
- What are the reservation, allocation, substitution, and cancellation rules when stock is insufficient?
- How are picklists grouped and prioritized for pre-camp operations and handover locations?
- Who may accept returned assets, and how are inspection disputes or partial returns resolved?
- How are responsibility and charges determined when assets are missing or returned in non-stockable condition?
- Are invoices issued by this platform or delegated to an external payment/accounting system?

### Participant registration and safeguarding

- Which occasion roles require registration, and may one registration cover multiple roles or role contexts?
- Which government bodies participate in the safe-from-harm evaluation, and what data exchange and response protocols do they require?
- Is the evaluation performed before registration is accepted, or may a registration remain pending while it is evaluated?
- What participant consent is required before importing data from a scout organization's member-service system?
- Which fields may be imported, and how are imported values reconciled with participant-provided values?
- Who may view or act on health, allergy, emergency-contact, and safeguarding information, and for which purposes?
- What retention, correction, deletion, and disclosure rules apply to sensitive registration and evaluation data?
- How are registrations for minors handled, including guardian consent and authority to submit or change information?

### Closed-loop payments

- Does the RFID wristband contain account data or only a token/reference to an internal account?
- What happens when a wristband is lost, damaged, duplicated, or transferred to another participant?
- Which reader devices and operating environments are supported, and can transactions continue during temporary offline operation?
- What transaction limits, refund rules, fraud controls, and administrative adjustment rules apply?
- How are external top-ups authorized, confirmed, reversed, and reconciled with the internal ledger?
- How are remaining balances settled or refunded at the end of the occasion?
- Which parties may view transaction history, balance information, or funding-source information?

### Occasion operations and support

- Which ticket categories, severity levels, response targets, and escalation paths are required?
- Which issues are safety-critical, and who may access or manage their restricted information?
- How are tickets created by participants, volunteers, support desks, telephone/radio operators, or external integrations?
- Which camp-site objects and geographic locations may be linked to tickets, and how are locations maintained during the occasion?
- How are duplicate reports, related tickets, recurring infrastructure problems, and major incidents grouped?
- What constitutes acknowledgement, in-progress work, resolution, and closure, and who may perform each transition?
- Which operational metrics and live views are required by management, dispatchers, team leads, and field personnel?
- How should tickets be handled when network connectivity is unavailable in the field?

### Closed-loop communications

- Which network infrastructure and fallback channels are available when the occasion network is congested or unavailable?
- Who may initiate, target, cancel, or override all-participant alarms and other emergency broadcasts?
- Which communications are available to all participants, and which require specific memberships, roles, or teams?
- What delivery guarantees, acknowledgement requirements, and escalation rules apply to alarms and critical messages?
- What moderation, abuse prevention, reporting, and safeguarding controls apply to direct and group messaging?
- Which message and media types must be retained, searchable, exportable, or deleted, and for how long?
- What are the capacity, recording, moderation, and access rules for one-to-many streams and 30–50-person n:n sessions?
- How are external recipients, such as guardians or emergency authorities, handled without compromising the closed-loop model?

### Environmental and food-safety monitoring

- Which monitoring points, sensors, inspections, and external data sources are required for water, food handling, air quality, and other environmental areas?
- Which thresholds, legal standards, inspection schedules, and escalation rules apply, and who maintains them?
- Which observations require sensor integration versus manual inspection or approval?
- How are sensor calibration, missing data, unreliable readings, and conflicting observations handled?
- Who may acknowledge, assign, override, or close an environmental or food-safety alert?
- Which threshold breaches require immediate communication, participant notification, service interruption, or authority involvement?
- What retention, reporting, and evidence requirements apply for compliance and post-occasion review?

### GIS-enabled camp planning and operations

- Which authoritative base maps, coordinate systems, site boundaries, and external geospatial data sources are required?
- Which geographic objects and relationships must be modeled for camp design, infrastructure, utilities, safety, transport, and participant services?
- Which planning workflows, approvals, design alternatives, and versioning rules are required before a design becomes operational?
- Which live data sources are available for traffic, incidents, alarms, tickets, sensor readings, and infrastructure status?
- How current must each operational layer be, and how are stale or unavailable data represented?
- Which GIS views and layers are available to participants, volunteers, team leads, dispatchers, and management?
- How are temporary closures, relocations, construction changes, and emergency zones represented and published?
- What export, printing, offline, and device requirements apply to field personnel and operational control rooms?

### Volunteer and occasion workforce management

- Which workforce types beyond volunteers are managed, and how do their employment or participation rules differ?
- Which recruitment, screening, interview, qualification, training, and safeguarding workflows are required?
- How are skills, certifications, availability, preferences, and language capabilities represented and matched to assignments?
- Can volunteers hold multiple simultaneous assignments, and how are conflicts, fatigue, rest, and maximum hours handled?
- How are attendance, shift changes, absence, reassignment, and handover recorded in the field?
- Which satisfaction and wellbeing data may be collected, who may access it, and how is anonymity handled in reporting?
- How are individual performance records distinguished from aggregate operational performance reporting?
- Which onboarding and offboarding actions must provision or revoke access to systems, teams, facilities, and communications?
- What retention and deletion rules apply to applications, interviews, safeguarding, wellbeing, and performance data?

### Fundraising and sponsor management

- Is sponsor management global across occasions or scoped to each occasion within its tenant, and how are multi-occasion agreements represented?
- Which sponsorship packages, contribution types, restrictions, approval workflows, and agreement terms must be supported?
- How are in-kind contributions valued, received, allocated, tracked, and reported?
- Which systems own sponsor invoicing, payments, contracts, branding inventory, ticket allocations, and benefit delivery?
- How are sponsor conflicts, category exclusivity, approval rights, and fulfillment disputes handled?
- Which relationship, pipeline, renewal, and sponsor-value metrics are required by the fundraising organization?

### Arrival and departure logistics

- Which participants, groups, suppliers, vehicles, and goods require scheduled slots or movement declarations?
- How are capacity limits, gate access, traffic priorities, staging areas, and emergency routes defined and enforced?
- How are transport plans coordinated when a group arrives with multiple vehicles, late changes, or incomplete manifests?
- Which arrival/departure statuses and operational checkpoints must be recorded for people, vehicles, and goods?
- How are delays, missed slots, congestion, breakdowns, lost goods, and unauthorized access escalated through the ticketing and communication systems?
- How are accessibility, safeguarding, privacy, and emergency-access requirements handled during movement planning?
- Which live traffic, gate, vehicle, and throughput data sources are available, and what level of offline operation is required?
- What post-occasion reports are needed to evaluate throughput, wait times, bottlenecks, incidents, and planning accuracy?

### Supply-chain management

- Which materials, consumables, assets, and services are planned centrally, and which may be sourced independently by teams or suppliers?
- How are camp designs, work packages, maintenance plans, and breakdown plans converted into supply requirements and bills of materials?
- How are sponsor-preferred suppliers, procurement restrictions, exclusivity, donated goods, and in-kind contributions handled?
- Which procurement workflows, approval thresholds, contract terms, and competitive sourcing requirements apply?
- How are substitutions, shortages, late deliveries, quality failures, and changing requirements managed?
- How should SCM and stock management divide responsibility for reservations, replenishment, transfers, maintenance, and disposal?
- Which delivery, staging, storage, and transport events must be coordinated with arrival/departure logistics?
- Which cost, readiness, supplier-performance, waste, sustainability, and post-occasion stock reports are required?

### Facilities and utilities management

- Which facilities, utility networks, and service capacities must be modeled and monitored?
- Which assets are owned, rented, sponsored, supplied by partners, or returned to suppliers after the occasion?
- Which installation, commissioning, inspection, maintenance, safety, and decommissioning workflows are required?
- Which utility readings and environmental conditions require automated monitoring versus manual inspection?
- How are planned outages, emergency failures, temporary repairs, and service restoration coordinated?
- Who may authorize changes to facility designs, utility connections, operating limits, and decommissioning plans?
- How are maintenance materials, spare parts, contractors, and specialist qualifications coordinated with SCM and workforce management?
- What evidence is required to prove that facilities and utilities were safely disconnected, returned, disposed of, or handed over?

### Security, access control, and threat prevention

- Which access technologies are permitted or required for gates, zones, vehicles, credentials, wristbands, and guard checkpoints?
- Which restricted zones, access conditions, escort rules, and emergency overrides must be modeled?
- Which participants, teams, suppliers, visitors, and authorities may receive which credentials, and for what periods?
- How are visitor registration, identity verification, host responsibility, vehicle access, and visitor departure handled?
- Which monitoring sources are allowed, and how are false positives, suspicious activity, alarms, and evidence managed?
- What is the escalation model for security incidents, suspected attacks, perimeter breaches, missing persons, and emergency access?
- How are security operations coordinated with government bodies, police, emergency services, and occasion incident command?
- What privacy, retention, access-review, and deletion rules apply to access logs, monitoring data, and security evidence?

### Calendar, scheduling, and capacity management

- Which activity types, calendars, approval states, recurrence rules, and dependencies are required?
- Which resources may be booked, and are bookings exclusive, shareable, capacity-based, or condition-dependent?
- How are personnel availability, qualifications, workload, rest periods, and shift conflicts enforced?
- How are venue, vehicle, equipment, infrastructure, and communication capacities represented and reserved?
- Who may create, approve, change, cancel, or override schedules, and how are changes communicated?
- How are late changes, substitutions, no-shows, cancellations, and emergency reprioritization handled?
- Which scheduling data must be available offline or synchronized to field devices?
- Which utilization, coverage, capacity, punctuality, and execution-performance reports are required?

### Performance, learning, and knowledge management

- Which events, measures, KPIs, and outcome definitions must every system record, and how are they standardized across systems?
- Which data may be used for AI evaluation, forecasting, recommendations, and cross-occasion learning?
- How should AI assess input quality, response correctness, recurring patterns, accident trends, similar orders, and stock forecasts?
- Which decisions may be automated, which require human review, and how are AI recommendations accepted, rejected, or corrected?
- How are false positives, biased evaluations, model drift, incomplete data, and conflicting insights handled?
- How are quality evaluations and lessons learned linked back to the original user input, system result, incident, order, or operational outcome?
- Which dashboards, alerts, forecasts, benchmarks, and post-occasion reports are required for each management layer?
- What privacy, retention, tenant isolation, access, and deletion rules apply to telemetry, user feedback, personnel performance, health, safeguarding, and financial data?

### Document, knowledge, and procedure management

- Which document and knowledge types require formal review, approval, expiry, acknowledgement, or training confirmation?
- Who owns, authors, reviews, approves, publishes, translates, and retires each type of operational guidance?
- How are documents scoped to occasions, roles, teams, locations, facilities, assets, and operational systems?
- Which content must be available offline, printable, translated, or accessible under field conditions?
- How are conflicting procedures, emergency overrides, corrections, and urgent publications handled?
- What search, tagging, metadata, relationship, and cross-system linking capabilities are required?
- Which document access, acknowledgement, change, and download events must be audited?

### Financial and economic planning and execution

- Which financial system is authoritative for invoices, payments, supplier obligations, settlements, and accounting records?
- Which planning and operational systems may create financial obligations, and which approval thresholds apply?
- How are participant charges, damaged or missing assets, supplier invoices, sponsor commitments, reimbursements, and payroll-like settlements represented?
- How are costs and revenue allocated across occasions, teams, camps, projects, work packages, sponsors, and funding sources?
- How are closed-loop payment balances, external top-ups, refunds, chargebacks, cash, and end-of-occasion settlement reconciled?
- Which financial controls, segregation-of-duties rules, approval workflows, tax requirements, and audit evidence are required?
- Which real-time dashboards, forecasts, budget variance reports, and post-occasion economic analyses are required?
- Which financial data may be shared with participants, suppliers, sponsors, volunteers, managers, and external auditors?

### Occasions and activities management

- Which activity types, approval stages, audiences, eligibility rules, and registration models are required?
- How are activities scheduled alongside shifts, venues, transport, meals, safeguarding constraints, and other commitments?
- How are capacity, waitlists, no-shows, cancellations, attendance, and last-minute changes handled?
- Which activities require dedicated staffing, qualifications, equipment, materials, suppliers, funding, or safety review?
- Who may right-size, relocate, combine, postpone, or cancel an activity, and how are affected participants notified?
- How are activity costs, revenue, sponsorship, participant charges, and resource consumption represented financially?
- Which demand, attendance, satisfaction, safety, cost, and execution metrics are required for management and post-occasion learning?
- What participant privacy, safeguarding, accessibility, and consent rules apply to activity registration and attendance data?

### CRM and relationship management

- Which relationship types, interaction types, cases, campaigns, and follow-up workflows are required?
- How are CRM ownership, handover, account teams, consent, communication preferences, and occasion-specific visibility managed?
- Which CRM data is authoritative when relationships overlap with participant support, fundraising, supplier management, or safeguarding?
- Which relationship health, engagement, conversion, retention, and service metrics are required?

### Emergency and incident command

- Which incident classifications, command structures, response plans, operational periods, and authority handovers are required?
- Who may declare, escalate, downgrade, close, or reopen a major incident?
- How are government bodies, police, fire, medical services, and external authorities integrated into command workflows?
- Which situation reports, resource requests, decisions, briefings, and evidence must be recorded?
- Which incident information requires restricted access, redaction, legal hold, or special retention?

### Transport and traffic management

- Which transport modes, vehicle types, permits, routes, parking areas, gates, and staging facilities must be modeled?
- Which live traffic, occupancy, dispatch, congestion, and route-closure data sources are available?
- How are emergency, accessibility, supplier, waste, shuttle, and participant movements prioritized?
- Who may change routes, close access, issue vehicle permits, or override traffic plans?
- Which traffic, throughput, wait-time, emissions, safety, and transport-cost reports are required?

### Food-service and catering management

- Which meal types, kitchens, serving points, suppliers, menus, and dietary categories must be supported?
- How are meal demand forecasts derived from registration, activities, attendance, and operational changes?
- How are allergy and dietary requirements communicated to food-service personnel while preserving confidentiality?
- How are production capacity, substitutions, shortages, surplus, waste, payment, and meal distribution handled?
- Which food-service inspections, traceability, hygiene evidence, and incident responses are required?

### Data integration and occasion-platform services

- Which system is authoritative for each shared master-data entity and operational record?
- Which integrations require real-time events, scheduled synchronization, imports, exports, or offline reconciliation?
- How are identifiers, versions, duplicate records, schema changes, retries, failures, and conflicting updates handled?
- Which external systems and government or scout-organization interfaces must be supported?
- What platform-wide requirements apply to search, workflow, notifications, audit, observability, data quality, and tenant isolation?
- Which data exchanges require explicit consent, minimization, encryption, approval, or special retention?

## Adopted access, integration and lifecycle requirements

- Initial signup uses an email/phone magic link. Subsequent choices are magic links, six-digit email/SMS codes or OpenID Connect; username/password authentication is excluded. Lost-phone recovery requires an authorized higher-permission user to vouch and supply a new verified phone/email.
- Multiple signup/signin slugs resolve tenant, occasion and organizational/team levels (including function leads, function teams and patrols). Slugs select scope, not authentication or unrestricted authority.
- Any user may invite another, subject to their team lead vouching before admission. Invitees can be assigned to an existing organization or a newly established one. Retiring an organization retires its assigned users' organizational access/assignments; unrelated valid contexts remain separate.
- Machine credentials are tokens created by occasion admins and manually rotated/revoked on request. Tokens can optionally be bound to MVs; current protected control state governs validity.
- A user's scoped role set bounds navigation, visibility and mutations. LISA's roles share one membership without mandatory participant/volunteer mode switching. Function leads select patrol staff only within their function and may delegate that bounded authority.
- Import matching uses email, phone or postal address plus name, with source trust and ambiguity checks. Similar records that cannot safely merge enter a yellow-list WorkItem for Participant Experience and Programme Lead; matching does not confer authentication-account control.
- Tenant admins create queues and configure their background jobs, bind MVs to queues, stop MVs to revoke serving/access, and revoke assigned tokens. Erasure-propagation windows are configurable but must honor privacy deadlines; serving suppression is immediate while physical cleanup is pending.
- Tenant admins configure application access as tenant-wide or occasion-wide. Vendors remain isolated; bindings limit contexts rather than waive field/purpose controls or isolation verification.
- Each new occasion has an admin-set expiry date/duration. Crossing it creates a tenant-admin review task to expire or prolong; a pending decision does not authorize indefinite retention or new intake. After retirement only opted-in eligible personal data are reconstructable, subject to purpose/period, erasure and independently justified restricted records.
- A protected subject index covers every backup and its dependencies. Approved erasure requests generate retrieval tasks for offline backups, isolated sandbox sanitization, verified replacement and destruction/retirement of originals. Restore suppression prevents resurrection while unresolved media removal remains tracked.
- Each occasion configures mandatory safeguarding/qualification evidence age limits; missing, stale or revoked evidence blocks appointment/assignment acceptance.

Detailed workflows and implementation safeguards are in [system_1_plan.md](system_1_plan.md); privacy obligations remain in [gdpr.md](gdpr.md).
