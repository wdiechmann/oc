# GDPR — Solution-Wide Data Protection Requirements

## Status, scope and terminology

This document defines the compliance baseline and engineering acceptance requirements for the entire solution, every native or independent in-house application, every third-party integration, and the event protocol. It complements [domain.md](domain.md), [entity-relationship.md](entity-relationship.md), [organization.md](organization.md), [suggested_systems.md](suggested_systems.md), [prioritized_functions_systems.md](prioritized_functions_systems.md), [suggested-data-store.md](suggested-data-store.md), [system_1_plan.md](system_1_plan.md), and [use_cases.md](use_cases.md). Requirements apply across **tenant > occasion > event**, including tenant/global identity processing outside an occasion.

**Legal baseline reviewed: 12 October 2026.** GDPR is Regulation (EU) 2016/679. “DPA” may mean a supervisory data protection authority or a data processing agreement; neither is a separate EU regulation called “GDPR DPA.” This document is a design and operational baseline, not a signed processing agreement or evidence that the implemented solution is compliant. Actual controllers must adopt the processing purposes, legal bases, contracts and jurisdiction-specific rules before processing begins.

Protection is not limited to EU citizens: applicability depends on establishment and processing circumstances, not nationality alone. Identifiable participants, guardians, volunteers, operators, suppliers and other natural persons are within the personal-data inventory. Organizational or machine records are also personal data when they identify a human, record an operator's activity or permit inference about someone. See [EDPB — Data protection basics](https://www.edpb.europa.eu/sme/learn-the-basics/data-protection-basics_en) and [territorial-scope guidance](https://www.edpb.europa.eu/documents/guideline/guidelines-32018-on-the-territorial-scope-of-the-gdpr-article-3-version-adopted_en).

Use the [GDPR text](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679) as the legal anchor: principles and lawful processing (Articles 5–10); transparency and individual rights (12–22); accountability, design, contracts and records (24–30); security and breaches (32–34); impact assessment and consultation (35–36); DPO assessment (37–39); and international transfers (44–49). The controls below are concrete implementation requirements chosen for this architecture, not claims that GDPR prescribes particular table names or algorithms.

## Accountability and legal responsibility

Technical roles do not establish legal roles. A `tenant_admin`, `occasion_admin`, platform operator, Board member or camp chief does not automatically become the controller merely by holding that permission. Identify the actual person/legal entity determining purposes and essential means for each processing activity.

| Processing relationship | Required decision and evidence |
|---|---|
| Tenant/occasion organizer | Identify the controller for registration, recruitment, camp operations and other activities; record accountable contacts and privacy notices. |
| Platform provider | Determine its processor role for tenant services and any separate controller role for its own signup, security or billing purposes. Global canonical identity ownership is technical mastering, not a legal entitlement to reuse data. |
| Participating scout corps | Assess whether they are separate controllers, processors or joint controllers for specific flows; Board representation does not answer this automatically. |
| Jointly determined processing | Record an Article 26 allocation, contact route and accessible essence of the arrangement when joint controllership applies. |
| Hosting, identity, SMS/email, cloud, analytics, SaaS and support vendors | Classify each activity, identify subprocessors and execute applicable processing contracts before access. Independent controller processing needs its own sharing rationale and transparency. |

The parties' actual decisions determine their roles; contractual labels alone are insufficient. Processing agreements must make instructions, confidentiality, security, assistance, subprocessing, audit and exit obligations concrete. See [EDPB — Controller or processor](https://www.edpb.europa.eu/sme/learn-the-basics/data-controller-or-data-processor_en) and [Guidelines 07/2020](https://www.edpb.europa.eu/system/files_en?file=2023-10%2FEDPB_guidelines_202007_controllerprocessor_final_en.pdf).

Assign a controller-approved privacy lead, identity/data stewards, application owners, rights-request coordinator, incident lead and retention owners. Assess and document whether a DPO is mandatory, including large-scale core monitoring or special-category processing; do not assume volunteer status or organizational size removes the obligation. Where appointed, preserve independence, resources and direct senior-management access. See [EDPB — Data Protection Officer](https://www.edpb.europa.eu/sme/be-compliant/data-protection-officer_en).

Maintain one inventory/record of processing activities covering all 25+ systems, not merely the shared database. Register purposes, people/data categories, legal basis, controller/processor roles, recipients, source/import paths, transfer locations, retention rules, security controls and accountable owners. Each application contributes and updates its entries; architecture and vendor changes trigger review.

## Purpose, lawful basis and special categories

Every collection, command acceptance, subscription, query, calculation, export and further use must have an approved purpose and applicable lawful basis. A role grant, consent-looking checkbox, contract clause or event history alone is not a lawful basis. Do not retroactively substitute a convenient basis when consent is withdrawn.

Map each purpose to a justified Article 6 basis. If data reveal health, religion or another special category, also establish a valid Article 9 condition. Criminal-conviction/offence checks require their distinct Article 10 and national-law assessment. Routine camp logistics cannot claim emergency necessity merely because a safety system exists. See [EDPB — Lawful processing](https://www.edpb.europa.eu/sme/be-compliant/process-personal-data-lawfully_en).

| Processing area | Required assessment before activation | Engineering consequence |
|---|---|---|
| Signup, identity verification and tenant creation | Necessary service/account processing, security purposes and relevant notice | Collect only required identifiers; account creation is separate from optional marketing. |
| Occasion registration and participation | Necessary participation purpose, terms, guardian context and retention | Explain mandatory versus optional answers; no blanket consent for all applications. |
| Volunteer recruitment and staff assignment | Recruitment/selection purpose, checks, fairness and retention of unsuccessful applications | Restrict interview/welfare information and avoid unexplained automated rejection. |
| Health, allergies, disability and emergency contacts | Necessity, Article 6 and Article 9 condition where applicable, recipient and emergency-access rules | Separate restricted detail from general rosters, events and meal forecasts. |
| Safeguarding, screening and incident evidence | Applicable special-category/offence/legal authority and disclosure requirements | Case-level access, minimal eligibility status, reviewed holds and qualified recipients. |
| Payments and accounting | Transaction/settlement purposes and specific statutory record obligations | Separate required ledger evidence from optional purchase profiling or marketing. |
| Traffic, location, RFID/access and CCTV | Necessity and proportionality of identifiable tracking, monitoring and retention | Prefer operational location/aggregate flow; avoid continuous individual tracking by default. |
| Sponsor/CRM communications, photos and promotional use | Separate operational communication from promotional purpose and applicable marketing rules | Granular preferences, withdrawal/objection enforcement and publication review. |
| Analytics, AI, forecasting and next-occasion reuse | Compatible/new purpose, necessity, legal basis and meaningful anonymization assessment | Prefer anonymous aggregates; prohibit unapproved model training and cross-occasion profiling. |

For consent-based processing, record the purpose, notice/version, affirmative action, authority of the person consenting and withdrawal. Optional choices must be granular and withdrawal easy; recording a user's agreement to a retention period does not authorize unnecessary indefinite storage. For legitimate interests, retain the purpose/necessity/balancing assessment, with particular attention to children. The basis registry is a controlled decision register rather than user-supplied metadata that validates itself.

## Children and safeguarding

JOE has his required identity even without enabled interactive login. A guardian acts through their own authenticated identity with verified authority; identity existence does not justify collecting a child-owned email/phone or granting a guardian access to every record. Provide age-appropriate information and review guardian authority as circumstances change.

Article 8 concerns consent-based information-society services offered directly to children; it is not a universal consent age for every camp activity. Denmark's cited consolidated law sets 15 for that specific situation, with guardian authorization below it; apply the current relevant jurisdiction and service assessment rather than hardcoding one age for all processing. See [Danish Data Protection Act, §6(2)–(3)](https://www.retsinformation.dk/eli/lta/2024/289/pdf).

Separate participation permission, guardian relationships, special-category consent where relied upon, media choices and app signup. Prevent children appearing in public directories by default. Safeguarding case visibility follows qualified purpose/authority, not the scout team hierarchy. Age/guardian checks should collect proportionate evidence, not unnecessary identity-document copies.

## Transparency and individual rights

Give clear notices at collection and cover imported data through the applicable indirect-collection notice process. Explain controller contacts, purposes/bases, categories/sources, recipients/transfers, retention criteria, mandatory fields, rights and relevant automated decision logic. Notice versions must be retrievable without exposing another person's data.

Provide an accessible rights route even after account closure or membership expiry. The controller normally responds within one month; a justified complexity/volume extension can add two months, with notice within the initial month. Proportionately verify requester identity and guardian/representative authority; protect other people's information. Rights and exceptions depend on the processing context. See [EDPB — Individuals' rights](https://www.edpb.europa.eu/sme/be-compliant/respect-individuals-rights_en).

| Request | Solution-wide behavior |
|---|---|
| Information/access | Discover data across source stores, event envelopes/details, MVs, vendor mappings, logs and reports; provide a intelligible copy and required processing information, not an unexplained raw event dump. |
| Rectification | Correct current authoritative records and derived views; annotate/correct historical claims as appropriate, retaining justified evidence without displaying inaccurate facts as current truth. |
| Erasure | Assess eligible records and exceptions per purpose/controller; execute and verify distributed removal rather than only hiding a profile. |
| Restriction | Mark and enforce restricted processing across handlers, queries, subscribers and derived jobs; permitted storage or other exceptions remain explicitly bounded. |
| Objection/consent withdrawal | Stop affected processing and downstream dissemination under the applicable rule; direct-marketing objection must stop that use. Do not cancel unrelated lawful purposes automatically. |
| Portability | Provide machine-readable data for qualifying consent/contract automated processing and support transfer where applicable; distinguish this from broader access rights. |
| Automated decisions | Assess solely automated decisions with legal or similarly significant effects; establish any permitted route and safeguards, including human intervention/contest mechanisms where required. |

Track request owner, receipt time, verification, scope, decision, holds/exceptions, downstream tasks, completion evidence and communications. Notify relevant recipients of correction/erasure/restriction as required, with a documented assessment of applicable exceptions. A failing vendor does not pause the controller's response obligation.

## Tenant, occasion, identity and operator boundaries

Tenant creation must collect/controller-configure privacy responsibility before the tenant imports personal data or opens recruitment. Do not assume a self-service creator has authority over all uploaded people. Occasion setup references the controller, approved purposes, notice, retention policy and recipients before intake is enabled.

Tenant-wide administration is broad technical administration, **not unrestricted inspection of all personal data**. Apply necessity, purpose, field and case-level restrictions to tenant admins, occasion admins, support users, deputies and application principals. Cross-occasion use within the same tenant needs an approved purpose and authorization; common tenant ownership is not sufficient. Cross-tenant identity/contact matching must not disclose another controller's relationships or profile.

Human and mechanical/electronic contacts retain required identities while active; organizational contacts may have an identity or none. Organizational actions preserve actual real-user operator, represented identity and delegation. These identifiers and activity logs require their own retention/access controls. Retiring personal records after their justified lifecycle is compatible with the identity invariant: the invariant does not require retaining an identifiable inactive contact forever.

## Event protocol and acceptance logic

The event log records accepted facts; it is not exempt from data protection because it is authoritative or append-only. Apply these requirements to commands, envelopes, JSON payloads, snapshots, outbox/inbox, retries, quarantine, notification templates, integration messages and calculation evidence.

| Control | Required protocol/handler behavior |
|---|---|
| Purpose and classification | Register event types with owner, permitted purposes, personal/special-category fields, audience, retention class and approved representations. Reject undefined or overbroad personal fields. |
| Scope | Validate tenant/occasion parent binding and object ownership. Global identity events have separately authorized scope, not an unrestricted broadcast audience. |
| Authority and necessity | Authenticate actual operator/service, represented identity and delegation; check current purpose-specific authority and allowed fields before acceptance. |
| Lawful processing policy | Validate applicable approved purpose/basis/consent or restriction state where needed. A command cannot authorize itself by supplying a legal-basis code. |
| Minimization | Use references to restricted/versioned records instead of copying health narratives, emails, names or safeguarding evidence into every event. Minimize free text and exception dumps. |
| Provenance/accuracy | Preserve source/version and distinguish reported observation, accepted status and human decision. Correct inaccurate current results without silently rewriting the meaning of prior decisions. |
| Security | Protect event metadata as well as payloads; exclude secrets/tokens; encrypt transport/storage where appropriate and restrict key/administrator access. |
| Subscriber admission | Authorize each tenant/occasion, purpose, type and field representation; no raw-log subscription just because a consumer is registered. |
| Lifecycle | Define correction, restriction, retention and erasure behavior for every event type, including linked individuals and multi-person payloads. |
| Derived processing | Carry restriction/expiry signals into jobs, exports and calculations; background execution has the same privacy obligations as interactive operations. |
| Evidence | Retain minimal policy/approval and processing evidence for its justified period; evidence is not an excuse to preserve the original personal payload indefinitely. |

Maintain a restricted `processing_policy` registry and a `data_subject_reference` index linking affected people to events, payload segments, artifacts, projections and external bindings. These are proposed implementation structures, not GDPR-prescribed tables. Index every affected subject, not only the actor; indexes themselves are personal data. Use opaque subject references, current restriction/expiry state, and narrow steward access.

For an external effect, verify purpose/authorization at its execution boundary as well as at command acceptance where changes can invalidate permission. Cancellation, restriction or withdrawal after enqueueing must be considered before dissemination. Replays and historical schema upcasters cannot reactivate a prohibited use or distribute deleted fields.

## Retention, erasure and replay

Define purpose-based schedules before collection, with triggers, maximum periods, responsible owner, archive conditions and specific hold reasons. Do not invent one universal camp retention period. Membership windows, occasion closure, consent preferences and vendor defaults are inputs; accounting, safeguarding and incident retention need their own justified decisions.

| Data class | Retention design requirement |
|---|---|
| Login verification/recovery and sessions | Short security-specific lifetime; exclude codes/secrets from permanent event payloads. |
| Active identity and membership records | Retain only for continuing justified relationships; assess global identity separately from each occasion. |
| Recruitment applications | Distinguish accepted staff from unsuccessful/withdrawn candidates; optional talent-pool retention is separately justified. |
| Health/guardian/safeguarding information | Purpose-specific access and deletion triggers; isolate narrowly retained evidence from routine participant profiles. |
| Payment/accounting records | Apply identified jurisdiction-specific obligations; do not retain unrelated personal detail because a ledger entry remains necessary. |
| Communications, location/access and CCTV | Short operational schedules unless a justified investigation/hold applies; no default permanent activity dossier. |
| Domain/security audit and administrator attribution | Explicit necessity, access and retention; audit is a processing purpose requiring justification. |
| Anonymous aggregate learning | Retain only after assessing reidentification and small-group disclosure; pseudonymized data remain personal data. |

**Business immutability must coexist with governed erasure.** Prefer minimal event envelopes plus separately controlled personal payload/reference stores. Where erasable information is embedded, support authorized payload/envelope-field redaction, segment removal or a compaction/replacement process that preserves required nonpersonal history and records minimal proof of the operation. A tombstone or appended `ErasureCompleted` event does not erase earlier personal data. Per-subject keys may help only when all relevant ciphertext, keys, replicas and identifiable metadata are addressed; cryptographic erasure is not an automatic legal conclusion.

1. Receive and assess the request/expiry under the controller's authority; identify other people, purposes and specific holds.
2. Restrict affected dissemination and consumers as appropriate while processing, and resolve in-flight work.
3. Remove or redact eligible personal data in sources, event details/envelopes, snapshots, consistency state, MVs, caches, indexes, broker retention, outbox/inbox, quarantine, objects, devices and exports.
4. Issue scoped vendor/subprocessor instructions and obtain completion or exception evidence; reconcile all known copies.
5. Maintain only necessary, restricted completion evidence and any specifically justified retained subset; communicate the decision and unresolved issues.
6. Ensure replay/upcasters consult the current deletion/restriction registry before materializing history. Missing erased payloads produce defined redacted/unavailable state, not retries that resurrect old copies.

The adopted backup policy requires a restricted subject-to-backup index for every backup and dependency chain. Approved erasure creates custodian tasks to bring offline copies online in an isolated sandbox, sanitize subject data, verify replacement backups and retire/destroy original media/versions. Merely deleting a sandbox restore does not remove the original backup. Record immutable/inaccessible media as unresolved, with deadline and escalation, and enforce restore suppression until physical removal is verified; do not claim deletion is complete while originals remain. Minimize and expire the index itself under its justified purpose. Exercise replacement, incremental-chain integrity and suppression in restore tests. Legal holds have reason, scope, authority and review/expiry; they do not authorize unrelated use or indefinite blanket retention.

Tenant-admin erasure windows schedule propagation but do not suspend the controller's obligations or permit indefinite retention. Suppress affected serving/dissemination promptly while background removal is pending; missed windows escalate and stopped MVs still receive required cleanup. Occasion-expiry review or prolongation must not silently override purpose-specific limits or user choices. Retired-occasion reconstruction includes only eligible opted-in personal data; restricted independently required records are not ordinary replayable profiles.

## Near-real-time MVs, calculations and dissemination

MVs are personal-data stores even though derived and rebuildable. Their update jobs must enforce authorized scope, purpose, field visibility, retention and restrictions. Security checks cannot rely on a lagging projection of consent, revocation or restriction when that would permit prohibited use.

- Default queries to minimal scoped MVs; separate health/case views from directories, staffing and participant views.
- Track input lineage, source versions, projection generation, effective restriction/expiry and processing lag. Delete/correct affected rows and derived outputs, not only the original record.
- Update dependent consolidations using approved source cutoffs and suppression rules; prevent small-group or joined views from reidentifying people.
- Exports and dissemination workers recheck permitted recipients/purposes and record the disclosed representation, not unrestricted raw payloads.
- Shadow rebuilds, staging stores, test fixtures and AI/evaluation datasets receive the same protection as live outputs. Use synthetic data in development by default.

## Application obligations and onboarding contract

Every application must meet the same privacy outcomes even if it does not implement the event protocol internally. A gateway cannot make noncompliant vendor storage, admin access, exports or reports compliant. Require an approved application privacy record before production personal data is supplied.

| Application evidence | Mandatory acceptance item |
|---|---|
| Responsibility and instructions | Controller/processor classification, owner, purpose, lawful basis, instructions and applicable contract. |
| Inventory and flows | All collected/derived fields, endpoints, MVs, logs, analytics SDKs, notification providers, devices and onward recipients. |
| Isolation and access | Tested tenant and sibling-occasion boundaries; least privilege, field/case restrictions, actual-operator attribution and support access. |
| Rights interfaces | Search/access/export, correction, restriction, objection/withdrawal and deletion APIs or reliable documented processes, with ownership and completion evidence. |
| Lifecycle propagation | Safe retries, policy/revocation/retention updates, rebuild behavior, backup handling and vendor exit; no resurrection through resynchronization. |
| Contracts and locations | Processing agreement, subprocessor authorization/change process, country/location inventory, support access and transfer mechanism. |
| Security and incident assistance | Risk-based measures, testing, credential/key controls, incident contacts, prompt processor notification and evidence availability. |
| Operational commitments | Numeric internal deadlines for rights tasks, restrictions, deletions and incident escalation that allow controllers to meet their obligations. |
| Change/exit | Prior review for new purposes/fields/vendors; export/return and verified deletion at termination subject to justified legal retention. |

An Article 28 agreement addresses processing subject/duration, nature/purpose, data/subject categories, controller rights, documented instructions including transfers, confidentiality, security, authorized subprocessors, rights/DPIA/breach assistance, return/deletion and audit information. Build concrete service obligations around these provisions rather than treating a generic vendor privacy policy as the agreement. See [EDPB — Controller/processor guidance](https://www.edpb.europa.eu/system/files_en?file=2023-10%2FEDPB_guidelines_202007_controllerprocessor_final_en.pdf).

## International transfers

Inventory storage, backups, subprocessors, remote support and onward disclosure outside the EEA. EU-region hosting alone does not resolve third-country recipient access. Confirm the relevant adequacy decision or appropriate safeguards and any necessary transfer assessment/supplementary measures; reassess when recipients or legal circumstances change. Exceptional derogations are not a routine integration strategy. See [EDPB — Transfer tools](https://www.edpb.europa.eu/topics/international-transfers-and-international-cooperation/tools-for-transfers-and-derogations_ga).

Block new destinations/subprocessors until reviewed and bind approved transfer routes into application onboarding and egress policy. The rights/disclosure inventory must identify what went where, so downstream correction, restriction and deletion can be coordinated.

## Security, incidents and notification

Apply risk-based technical and organizational security: least privilege, strong privileged authentication, encryption and key separation where appropriate, secure development, patching, network/runtime isolation, scoped service credentials, access review, restore testing, incident detection and trained operators. Keep emergency break-glass access purpose-limited, bounded and audited; afterward review actual disclosures.

A personal-data breach can involve confidentiality, integrity or availability, including wrong-tenant disclosure, lost offline devices, exposed event payloads or corrupted health/authorization records. Processors notify their controller without undue delay; controllers assess supervisory-authority notification without undue delay and, where feasible, within 72 hours of awareness unless the risk exception applies. High-risk affected-person communication has its own assessment. Document all breaches and reasons for decisions, including nonnotification. See [Datatilsynet — Breach notification](https://www.datatilsynet.dk/sikkerhedsbrud/anmeld-sikkerhedsbrud).

Record awareness time, controller/tenants/occasions, affected data/people, likely consequences, containment, notifications and updates. Incomplete information is not a reason to wait until investigation finishes; use justified phased updates. Vendor and internal escalation targets must leave time for controller assessment. Notify the competent authority, not automatically Denmark for every possible tenant.

## DPIA, automated processing and release gates

Screen each processing activity and significant change for DPIA requirements. The camp's children, health information, linking across systems, possible tracking/CCTV and scale justify treating a coordinated DPIA as a delivery requirement, while assessing each high-risk activity specifically. This is a project decision based on risk, not a claim that every application always needs a separate DPIA. Record necessity/proportionality, threats to individuals, mitigations, residual risk and review owners; required prior consultation precedes activation where high residual risk remains. See [EDPB — Compliance and DPIA guidance](https://www.edpb.europa.eu/sme/be-compliant/be-compliant_en).

AI-assisted safeguarding, recruitment ranking, performance scoring and personal predictions need separate assessment. Keep observations, model recommendations and human decisions distinct. Do not enable vendor model training on camp data by default. A human review must be meaningful where used as a safeguard; automatic refusal hidden behind a nominal reviewer is insufficient.

| Delivery gate | Required evidence |
|---|---|
| **P0: identity, tenant and protocol foundation** | Controllers/purposes identified; processing inventory, privacy defaults, policies/notices, DPO assessment, event schemas, restriction/erasure model and isolation tests. |
| **Before recruitment/registration opens** | Approved purposes/bases, child/guardian routes, specialist-data conditions, notices, retention schedules, rights workflow and applicable contracts; necessary DPIA work complete. |
| **Before each application receives personal data** | Onboarding contract/evidence, verified fields/audience, isolation, transfer assessment, rights/deletion support and breach contacts. |
| **Before live camp operation** | End-to-end rights, restriction/deletion, restore/replay and breach exercises; monitoring, trained staff and residual-risk decisions. |
| **Closure and ongoing operation** | Holds reviewed, expired data removed, vendors reconciled, access retired, approved archives/anonymous learning separated, and continuing-purpose records justified. |

Acceptance tests must prove multi-person event discovery; tenant/sibling isolation; bounded organization-operator access; restricted child/case views; consent withdrawal before a queued message; deletion from MVs and replay; restored-backup suppression; vendor correction/deletion evidence; right-request deadline tracking; and incident notification readiness. Publish completion evidence and named unresolved decisions; do not describe document creation, encryption, or an audit log alone as GDPR compliance.

## Outstanding controller decisions

Identify actual legal entities and jurisdiction-specific roles; approve purpose/basis and special-category/offence conditions; adopt explicit retention periods and hold rules; finalize processor/subprocessor agreements and transfers; resolve DPIA/DPO conclusions; and assign operational owners and numeric internal deadlines. Review this baseline when legislation, guidance, purposes, architecture or vendors change, and before a later occasion reuses personal data from an earlier one.
