# Pending monitoring deployment details

The current work is authorized for **local implementation and local rehearsals**. No production deployment, real alert send-out, production backup access or destruction of original backup media is implied.

| Detail | Needed before deployment | Local implementation/testing |
|---|---|---|
| Collector/probe placement | Hosts, service supervisor, restart policy, network boundaries and an independent failure domain | Local standalone process with fixed configured targets; no dependency on EP's database to record an outage. |
| Probe targets and service objectives | Approved URLs, availability/latency/lag thresholds, maintenance windows and escalation times | Loopback targets and configurable defaults; local test outcomes are not production capacity evidence. |
| Alert ownership and delivery | Duty identities, on-call schedule, SMTP/provider credentials, fallback channel and runbooks | Fake recipients/private development sink only; no real external email. |
| Application/source admission | Approved backend IDs, scope bindings, owners, token custody and rotation/revocation procedure | EP-governed registration/discovery and current-scope checks; local fixtures for isolation. |
| Spool custody | Storage paths/quotas, filesystem guarantees, durable volume, encryption-key custody/rotation and loss response | Private encrypted bounded files with explicit overflow/expiry/quarantine counters. |
| Restricted access | Named platform operators, diagnostic readers and privacy operators; periodic access review | Explicit permissions, not automatic elevation of tenant administrators. |
| Retention | Approved detail/issue/security schedules, holds, erasure deadline and cleanup ownership | Implemented fixed cleanup defaults and safe local fixtures; approved policy configurability remains pending; no claim that a default alone establishes compliance. |
| Backup inventory | Locations/formats, full/incremental dependencies, per-copy subject coverage, custodians and offline/immutable copies | Local manifest/rehearsal workflow; no production originals are modified or destroyed. |
| Backup erasure closure | Retrieval schedule, sandbox isolation, replacement verification, retirement/destruction evidence and immutable-media exceptions | A sanitized replacement alone never marks the original backup erased. |
| Browser verification | Playwright MCP availability, supported browser/device matrix and accessibility review | Request/client-logic tests can run locally; record browser checks as pending until actually executed. |
| Load/failover rehearsal | Representative request mix, user/producer concurrency, hardware/topology, expected sustained/burst rates and recovery objectives | Local synthetic results will be recorded with their workload and limitations. |

Record decisions and evidence here as they become available. Do not mark a production obligation complete based solely on a local rehearsal.

## Explicit coverage gaps before production acceptance

- Implement an independently delivered fallback alert/paging adapter and validate provider callbacks/bounces, responder escalation and runbooks; the current independent fallback is a private local notice plus stderr.
- Approve retention schedules and implement legal-hold/security-exception handling before enabling automatic deletion. Current cleanup defaults are 30-day diagnostics and 90-day monitoring content; policy configurability is still pending.
- Add and verify erasure adapters for identities, all business domains, attachments, ordinary application logs, vendors and every retained derivative. The implemented erasure/restore pass covers monitoring content only; it does not establish whole-solution erasure.
- Keep restored databases unpublished until the latest signed ledger is applied, all domain handlers pass, jobs/credentials are reviewed and publication is separately approved. Assign offline/immutable custodians and record original-copy retirement/destruction evidence; replacement creation alone cannot close a task.
- Decide privacy HMAC/backup encryption key custody, rotation/migration and long-term ledger retention. Inventory coverage currently includes registered identity hashes, not arbitrary personal references in unstructured content.
- Set configurable operational objectives and defaults, evaluate host loss/database outage storms, and run Playwright MCP desktop/mobile/accessibility checks when that tool is available. The local 200-request rehearsal is not a 40–80,000-concurrent-user capacity claim.
