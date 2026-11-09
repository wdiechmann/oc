# Communications UI — One Desk, Every Channel

## Product intent

Draft interface for system 8, Closed-loop communications: one workspace for email, SMS, social media (SoMe), internal messages, team conversations and operational broadcasts. Operators should see who needs a response, what has already been said, who owns the conversation and what can happen next without moving between provider inboxes.

Unify attention, context and workflow while keeping each channel's audience and delivery semantics visible. A public comment, private message, internal note and emergency instruction must remain unmistakably different at the moment of sending.

This is a proposed UI, not an implemented application or a claim that any provider is connected. It follows [domain.md](domain.md), [named_spaces.md](named_spaces.md), [use_cases.md](use_cases.md), [system_1_plan.md](system_1_plan.md), [system_5_plan.md](system_5_plan.md), [architecture.md](architecture.md), [gdpr.md](gdpr.md) and [names.md](names.md). No new product name is assigned here.

## The primary screen

A calm, dense operations desk with four persistent regions: navigation, conversation queue, conversation workspace and contextual inspector. Conversation and composition receive most of the width. Secondary detail collapses before message text becomes cramped.

```text
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ SL2030 ▾ / Participant service ▾   Search conversations, people, work…   Channels: 1 issue   Me ▾  │
├────────────────┬──────────────────────┬───────────────────────────────────────┬──────────────────┤
│ + New message  │ Needs attention  24  │ Water at North Camp                   │ Context          │
│                │ Filter ▾  Sort ▾     │ Group leader · identity unconfirmed   │ Owner: Service   │
│ My work      8 │                      │ Open · Owner: Anna · Response due 14:20│ Team ▾           │
│ Unassigned  12 │ ● North Camp         ├───────────────────────────────────────┤                  │
│ Team inbox  36 │   SMS · 4m · due 8m  │ 14:02  Incoming SMS                    │ People           │
│ Waiting     15 │   Is the water safe? │ “Is the tap near North Camp usable?”  │ Group leader     │
│ Scheduled    3 │                      │                                       │ Related group    │
│ Sent           │   Arrival question   │ 14:04  Internal note · Service only    │                  │
│                │   Email · 12m        │ “Facilities checking supply.”         │ Location         │
│ Shared inboxes │   Coach arrival      │                                       │ North Camp ↗     │
│ Participant    │                      │ 14:06  ASTER work linked               │                  │
│ Facilities     │   Public question    │ Water inspection · owner accepted     │ Linked work      │
│ Media desk     │   Social · 18m       ├───────────────────────────────────────┤ ASTER #1842 ↗    │
│                │   Opening hours?     │ Reply · SMS ▾ · From: Camp Service ▾   │                  │
│ Broadcasts     │                      │ To: +45 •••• 1234 · Private            │ Delivery         │
│ Live rooms     │                      │ [Write a reply…                      ]│ Received 14:02   │
│ Templates      │                      │ Attach  Template  Language  Preview   │                  │
│ Reports        │                      │ 128 characters · segments calculated  │ Preferences      │
│ Connections    │                      │ Save draft               Send SMS →   │ Service SMS ✓    │
└────────────────┴──────────────────────┴───────────────────────────────────────┴──────────────────┘
```

The example is illustrative. Counts, targets and delivery capabilities come from accepted state and configured providers. Changing tenant, occasion or team visibly changes the workspace; search and selections never silently carry into another scope.

## Navigation and attention

**My work** is the default landing page: assigned conversations needing a reply or a promised follow-up. Shared inboxes represent accountable services, not merely email addresses. A service may receive messages from several email accounts, phone numbers and social profiles.

| View | What belongs here |
|---|---|
| Needs attention | Unanswered inbound messages, overdue follow-ups, failed sends and unresolved handovers |
| Unassigned | New conversations without an accepted operator; the inbox team remains accountable |
| My work / Team inbox | Current accepted assignments within the selected scope |
| Waiting | Conversations awaiting the requester, another team or an external result, with review times |
| Scheduled | Drafts with an intended send time, approvals and audience checks |
| Sent | Outbound messages and channel-specific outcomes |
| Broadcasts | Audience-based announcements, campaigns and emergency notices |
| Live rooms | Authorized team rooms, audio/video sessions and broadcast streams |

Show an attention count separately from unread count. Reading a message does not answer it, acknowledge an assignment or complete work. Sort by operational urgency and due time, with an explainable reason; offer recent activity and oldest unanswered alternatives. Filters include channel, inbox, owner, language, tag, status, priority, location, linked work and delivery failure.

A queue row shows sender or group, subject/first line, channel, public/private marker, last activity, owner and response deadline where applicable. Restricted previews are withheld. Urgent items use an icon and label as well as color; routine messages do not compete with emergency banners.

## Conversation workspace

The header keeps subject, participants, identity confidence, audience, owner and next action visible. The timeline interleaves messages with meaningful operational milestones: assignment accepted, work linked, promised update, delivery failed and conversation reopened. Hide routine transport noise under expandable delivery details.

Each message carries channel/account, direction, author or represented organization, audience and timestamp. Public posts retain their post/comment hierarchy and source link. Email retains subject, sender, To/CC and quoted-history expansion. SMS remains a sequence of messages with provider delivery state. Attachments show filename, type, scan state and authorized preview.

Use distinct presentation for external messages, internal notes and system activity. Internal notes have a persistent “Internal · [audience]” label and tinted background. Restricted notes require their own authorized audience. A reply or forward starts a new explicit composition; it never inherits an internal note's body or hidden recipients.

When channels are linked, provide **All activity** and channel tabs. The timeline explains “Continued by SMS” rather than pretending an email and a text are the same transport thread. Preserve original provider IDs and provenance. Deduplicate imported copies without discarding original delivery evidence.

Selecting a message exposes Reply, Reply all where appropriate, Forward, Link work, Report abuse and View delivery. Bulk conversation actions cover assignment, tagging and status where permitted; bulk replies require a separate reviewed broadcast flow.

## Identity and conversation linking

Show a familiar sender label without overstating identity: **Verified platform contact**, **Known channel address**, or **Unconfirmed sender**. A matching display name, phone field or social handle is insufficient to authenticate a person or disclose their camp relationships.

Offer “Link to contact” with candidates visible only within current authority. Record who confirmed the link and its basis. Linking a social account does not turn it into a verified login identifier. Shared family addresses and phone numbers can represent multiple people; the operator must choose the relevant relationship rather than automatically merging identities.

Offer “Relate conversation” separately from “Combine view.” Cross-channel history remains permission-filtered. A combined operator view grants no additional visibility to external participants. Public comments never reveal a person's private support history. Preserve reversible links and original records; do not merge canonical contacts from the inbox.

## The composer

The composer is the central interaction. Keep **reply mode, channel, sending identity, recipients and audience** visible above the editor, and use a specific action label: **Send email**, **Send SMS**, **Reply publicly**, **Send private message**, or **Add internal note**.

1. Choose Reply, New message, Internal note, or Forward.
2. Confirm recipients and sending account. Suggest the inbound channel only if a reply is currently supported.
3. Write content or choose an approved template. Suggestions and translations remain editable drafts.
4. Review channel preview, attachments, language and any delivery limitations.
5. Send, schedule, or submit for approval according to authority and message class.

Channel switches retain a draft but require review of the new audience and rendering. Never silently convert a public comment into a private message, drop an attachment or truncate content. If a provider cannot support the selected action, explain the limitation next to that action and offer an authorized alternative.

| Channel | Composer behavior |
|---|---|
| Email | Subject, To/CC/BCC, reply-all review, rich/plain preview, attachments and signature; external recipients never see BCC addresses |
| SMS | Phone endpoint, sender label, live encoding/segment estimate, optional configured cost estimate and text/link preview; unsupported media needs an explicit alternative |
| Social private message | Provider/account badge, recipient handle and current messaging eligibility; show unsupported formats or reply restrictions |
| Social public reply | Persistent **Public** banner, parent post preview, visible profile and exact publish action |
| Social publishing | Account selection, per-platform variants, link/media preview, alt text, scheduling and approval |
| Internal/team message | Explicit team/room audience, mention permissions, attachment controls and acknowledgment option |

Actual lengths, encoding, attachments and reply windows come from the connected adapter's capability metadata; this draft fixes no provider-specific limits. SMS costs remain estimates until reconciled. No paid fallback, channel change or public publication occurs merely because another route failed.

Autosave drafts privately with clear Saved/Saving/Not saved states. A failed save or uncertain send preserves the draft. “Undo send” is offered only where a real local hold or provider capability supports it. Once delivered, cancellation cannot promise recall; use an explicit correction or follow-up.

## Collaboration and service work

Show who is viewing or drafting in the same conversation. Presence is advisory; accepted owner changes and send deduplication are enforced server-side. A handover contains the proposed owner, a short context note and next action; the existing owner remains responsible until acceptance.

Actions **Create ASTER work** and **Link existing work** open a side panel with a safe summary, category, location, classification and proposed team. Review which messages or attachments will be shared; do not copy the whole conversation by default. On acceptance, show work ID, authoritative status and accountable owner. Communication ownership and work ownership remain separately visible.

Resolving a conversation requires an outcome and may schedule follow-up. It does not close linked work automatically. A new inbound message reopens attention under the adopted policy while preserving previous outcomes. A “Waiting for facilities” label always includes who follows up and when.

## Broadcast studio

Use a dedicated flow for announcements to groups, roles, locations or selected contacts:

**Purpose → Audience → Content and channel variants → Review → Approve/send → Track**.

Audience review shows inclusion criteria, exclusions, channel availability, deduplicated people versus delivery endpoints, language distribution and the source freshness. Avoid exposing recipient addresses to one another. For changing groups, state whether membership is frozen or re-evaluated at execution; apply current restrictions, recipient eligibility and applicable preferences before sending.

Let the operator choose a preferred channel and an approved fallback strategy. Preview exactly what each recipient segment will receive, including SMS reductions and email detail. Shared endpoints, multi-channel delivery and intentional repetition must have an explicit policy. Marketing preferences, service notices and emergency instructions have distinct purposes and authorization; do not treat them as one global opt-in toggle.

Social publishing has account-specific drafts, approval, calendar and public preview. Its audience is **the platform's public audience**, not a known camp membership list. Keep public reach/engagement statistics separate from person-level delivery and acknowledgment.

The final review names the sending identity, purpose, audience size, scheduled time/timezone, channels, estimated SMS usage, required approval and unresolved blockers. Material edits invalidate approval. A test send goes only to explicitly selected test recipients and is visibly marked as a test.

## Emergency communications

Place **Emergency notice** in a separate, permission-gated operational area linked to incident command. Use a strong visual frame, approved templates and an always-visible instruction to follow the adopted emergency procedure when systems fail.

The review includes incident reference, issuing authority, affected area, audience basis, instructions, expiry, channels, acknowledgment requirement and escalation ownership. Apply the adopted emergency approval policy; do not invent a routine two-person requirement that could delay an authorized urgent action. An exercise is unmistakably labeled throughout composition, delivery and history.

The live view shows intended recipients, attempts, provider acceptance, delivery evidence where available, explicit acknowledgments, unreachable recipients and unconfirmed outcomes. Acknowledgment means the recipient actively confirmed; it does not prove safety, arrival or completed response. Offer follow-up cohorts such as “not acknowledged,” subject to current targeting authority.

Cancel stops eligible pending attempts. Publish a correction/all-clear as a new attributable communication; preserve links to the original. Public social announcements support the official response but cannot establish closed-loop receipt. Radio/manual fallback and incident-command responsibility stay visible during outages.

## Delivery, failures and degraded operation

Represent outcomes per recipient, channel and attempt. Conversation status is separate from transport state.

| Display state | Meaning and next action |
|---|---|
| Draft | Saved content; no send accepted |
| Scheduled / Awaiting approval | Intent exists; release conditions remain pending |
| Queued | Accepted send intent; no provider acceptance yet |
| Provider accepted | Provider accepted the attempt; delivery is unproven |
| Delivered | Channel-specific delivery evidence received |
| Read | Read evidence exists for that channel; explicitly not universally available |
| Acknowledged | Recipient explicitly acknowledged the communication |
| Failed / Blocked | Known failure or current policy/capability block, with a permitted action |
| Outcome unknown | Timeout or missing evidence; reconcile before retrying |
| Cancelled / Partially sent | Remaining eligible attempts stopped; earlier delivery remains possible |

Show connection trouble in the global status area and affected queues. Distinguish provider outage, expired account authorization, rate limiting, stale inbox synchronization and EP unavailability. Existing messages may be labeled stale; restricted access still requires current authorization. Do not turn cached data into an unrestricted offline inbox.

Uncertain sends use stable operation references and completion checks. Retry targets known eligible failures and shows possible duplication where a provider cannot reconcile. Offline drafts are explicitly unsent; reconnecting does not silently release them. A restored connection triggers current audience and authority checks before execution.

## Context, search and administration

The inspector shows authorized contact details, relationships relevant to this occasion, language/preferences, linked work, semantic location, owner, follow-up and delivery summary. Sensitive health, safeguarding and security narratives remain in their owning restricted applications. Each section states why it is visible when access depends on a special purpose.

Global search covers authorized messages, contacts, work references and attachments approved for indexing. Offer structured filters such as `channel:sms`, `owner:me`, `status:waiting` and date ranges. Enforce scope and current access for results, snippets, counts, exports and deep links. Deleted/restricted content cannot survive through a search preview.

Connections administration shows inbox/account owner, granted capabilities, synchronization health, last successful receipt, delivery health, pending failures and authorization expiry where known. Provider secrets never appear in ordinary account detail. Connection setup must review which services and audiences may receive or publish through that account.

Reports prioritize unanswered age, accepted handovers, response time, unresolved follow-ups, delivery uncertainty and acknowledgment coverage. Define metric denominators and available evidence. A social “seen” signal and an SMS delivery receipt must not be combined into a generic read-rate claim.

## Visual and interaction direction

Use a quiet neutral surface, strong readable typography and compact rows with generous message spacing. Reserve a restrained accent for selection and primary actions; warning and emergency treatments carry text/icons alongside color. Channel badges aid scanning without turning the interface into competing brand colors.

Desktop starts with approximately 200 px navigation, 300 px queue, a flexible conversation and a 280 px collapsible inspector. At narrower widths hide the inspector first, then use queue/conversation navigation. Mobile shows one pane with a persistent header and composer; audience and channel remain visible above the keyboard.

Support keyboard navigation, visible focus, screen-reader labels, announced send outcomes and accessible status changes. Provide optional shortcuts for search, next conversation, reply and internal note; sending always requires an explicit action, with no single-key global send shortcut. Keep focus and draft content stable as incoming messages arrive; show a new-message indicator rather than forcing a scroll.

Confirmations are proportional: routine private replies use the explicit send action; public publishing, changed audience, bulk messaging and emergency actions have a concrete review appropriate to their risk. Destructive or cross-audience actions cannot hide behind generic “OK” buttons.

## Delivery slices and review scenarios

1. **Unified service desk:** email, SMS and internal notes; scoped inboxes, contact references, accepted ownership, safe composer, delivery states and ASTER links.
2. **Social operations:** supported private messages, public comments and publishing; capability-aware drafts, account permissions, moderation, preview and approval.
3. **Audience communications:** multilingual templates, scheduling, explicit fallback, preference enforcement, audience review and reconciled delivery reporting.
4. **Operational channels:** team rooms, acknowledgment tracking and governed emergency notices tied to incident command. Live audio/video and streaming use dedicated session views; they do not crowd the asynchronous inbox. Adopt the domain's approximately 30–50 participant limit for n:n conferences pending operational validation.

Review the UI using realistic scenarios: a participant moves from email to SMS without leaking family history; a public comment becomes a private support case without exposing private replies; two operators answer at once; an SMS outcome is unknown; a duty handover is not accepted; a scheduled audience changes; a restricted case loses access mid-session; an emergency has unacknowledged recipients during a provider outage.

Acceptance requires that an operator can always identify **who is speaking, to whom, through which channel, with what visibility, who owns follow-up and what delivery evidence actually exists**. Provider selection, messaging costs, exact service targets, audience policies and emergency authority are decisions to settle before activating the corresponding capabilities.
