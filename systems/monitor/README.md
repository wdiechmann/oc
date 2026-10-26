# Independent monitoring collector

A separate Ruby standard-library process probes fixed loopback targets, keeps a bounded encrypted transport queue and forwards observations to EP's API. It has no database. The queue is a temporary delivery buffer; `event`/`event_details` remain authoritative. Run this process independently from the EP/TOM process supervisors in deployment; a local process on the same host cannot detect loss of that whole host.

## Local setup

1. Migrate EP, register an application source in TOM's Monitoring → Sources and alert rules, and provision a global source through an explicitly authorized platform operator. Use an approved backend ID and its backend token. Source UUIDs are not credentials.
2. Copy `config/local.example.json` to a private file (`chmod 600`), replace its absolute private spool path and source UUID, and configure fixed probe targets. Create the spool directory with mode 700. The example is a template, not a working credential/configuration.
3. Set `EP_MONITOR_CONFIG` to that file, `EP_BACKEND_TOKEN` to the approved backend credential, and `EP_MONITOR_SPOOL_KEY` to a base64-encoded random 32-byte key. Keep key/credential material outside source control and command arguments. EP's and TOM's corresponding spool must use the same directory/key as its accompanying collector. Use a separate collector per distinct spool/key.
4. Run `ruby systems/monitor/bin/monitor --once` to check configuration, then `ruby systems/monitor/bin/monitor` as a supervised service. Restart with the same key and volume. Do not run two collector processes against the same probe-state directory.
5. Run TOM's `bin/monitoring-worker` as a separate supervised process for alert delivery. Its default development sink creates private files, not external email. `/up/monitoring` reports its heartbeat. Configure a collector probe for it if required.

Collector endpoints bind only to `127.0.0.1:9910`: `/health/live`, `/health/ready`, `/status`, `/metrics`. Readiness distinguishes unhealthy dependencies, stalled delivery, quarantine and missing recent ticks. The process records an independent private `.notices` log and stderr notice even while EP is unreachable. A production fallback recipient/channel adapter is **pending**; local visibility alone does not page a person.

Three failed probes open a condition; three successful probes recover it. An open failure is reminded at most once per five minutes. Delivery drains ten records per tick, with exponential backoff (maximum five minutes), stable observation UUIDs and EP deduplication. Permanent rejection is quarantined instead of retried indefinitely. Follow loss/expiry/quarantine counters; do not erase quarantined evidence until its cause and disposition are recorded. Default limits: 10,000 records, 64 MiB, 24-hour queue age. Expiry is transport loss, not successful persistence. Inflight claims become reclaimable after 60 seconds. Do not modify queued ciphertext by hand.

EP telemetry capture is enabled by `EP_MONITOR_OBSERVER=true` and `EP_MONITORING_SOURCE_ID` (a global EP source). It aggregates database errors/pool pressure, request error/latency breaches, exhausted jobs and projection delay; no raw SQL or exception messages are ingested. Configure `EP_MONITOR_SPOOL_DIR` and `EP_MONITOR_SPOOL_KEY` for its independent fallback. TOM discovers source bindings through the backend-only API and queues before its fast delivery attempt. The file format is shared across Elixir and Ruby.

## Alerts and ambiguity

Rules use scoped catalogue codes, bounded windows, thresholds, cooldowns and explicit recipients/delivery backend. Suppression stops new notifications, not observations. EP creates a claimable alert intent; TOM sends it and reports `test_accepted`, `provider_accepted`, `rejected` or `unknown`. SMTP acceptance does not prove delivery. Expired claims become unknown and are never automatically resent. A durable outcome acknowledgment may be retried, but sending an email is not replayed. No provider callback/bounce adapter or on-call escalation integration is implemented yet.

## Privacy and backups

Monitoring diagnostics have a separate permission gate and 30-day serving limit. Approved monitoring cleanup redacts details and identifying links while preserving projection checkpoints. Subject HMAC tombstones suppress late buffered records and restored monitoring data. The stable privacy key is required across restores; rotating it requires an explicit migration of the index/ledger. Automatic 30/90-day cleanup is opt-in (`EP_MONITOR_RETENTION=true`); approved policies, holds and security exceptions remain deployment work.

Trusted operators can grant named permissions with `mix ep.monitoring.grant IDENTITY_UUID platform_monitor|diagnostics|privacy_operator SCOPE [--revoke]`, where scope is `global`, `tenant:UUID` or `tenant:UUID:occasion:UUID`. Granting diagnostics does not grant tenant/occasion administration. Record operator approval outside the bootstrap command before deployment. Privacy commands require a currently authenticated `EP_OPERATOR_BEARER` with global `privacy_operator`.

Backup tooling uses `EP_MONITOR_BACKUP_KEY` (base64 random 32 bytes) for authenticated AES-256-GCM and `EP_MONITOR_PRIVACY_KEY` for signed inventories/erasure ledgers. Set `DATABASE_URL` and `EP_MONITOR_PG_BIN` to PostgreSQL client binaries **matching the server major**. Use a private output directory. Commands, from `systems/ep`:

```text
mix ep.monitoring.backup capture /private/path/copy.epmon
mix ep.monitoring.backup ledger /private/path/current-ledger.json
mix ep.monitoring.backup worklist /private/path/current-ledger.json /private/path/copy.epmon.manifest.json
mix ep.monitoring.backup restore-local /private/path/copy.epmon /private/path/copy.epmon.manifest.json /private/path/current-ledger.json sl2030_monitoring_restore_trial
```

The snapshot and its subject inventory share one database snapshot. Inventory coverage is a registered-identity superset, not detection of every unstructured reference. Restore creates a **new loopback-only sandbox** and never overwrites an existing database. It stays unpublished. Point `DATABASE_URL` to that sandbox, then run `mix ep.monitoring.backup apply-ledger /private/path/current-ledger.json` The task configures isolated startup with no web endpoint or workers. Run it as a fresh command, never in an already-running web node. Fetch the latest ledger again before any contemplated publication.

**Coverage is monitoring only:** these commands do not erase identities, all business-domain data, attachments, general application logs, or third-party copies. A domain-wide erasure pass and independent verification are required before publication. The tooling has no publication action. Original/offline/immutable copies remain unresolved until custodians provide retrieval, replacement and original retirement/destruction evidence. Do not interpret a sanitized sandbox or signed manifest as full GDPR erasure completion. See [pending details](../../pending_details.md).

## Verification

```sh
ruby systems/monitor/test/spool_test.rb
ruby systems/monitor/test/agent_test.rb
ruby systems/monitor/test/server_test.rb
ruby systems/monitor/test/vault_test.rb
```

See [local rehearsal evidence](local_rehearsal.md). Production topology, independent alert delivery, real provider callbacks, browser/device checks and representative capacity evidence remain pending.
