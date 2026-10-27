# VERA guidelines

- VERA is a separate financial client/backend. Follow ../../system_2_plan.md and ../../finance.md.
- Use Rails 8.1, Ruby 3.4.4, Phlex views/components, Tailwind and locally served Turbo. Controllers rendering Phlex use `layout false`.
- No local business database, Active Record, direct EP SQL or shared TOM files/sessions. All business reads/commands use EP APIs with current authority. Keep credentials and private artifacts out of Git/logs.
- Keep financial domain acceptance/guards/events in EP. Near-real-time MVs serve queries and do not authorize money movement. Preserve expected versions/idempotency and unknown-outcome reconciliation.
- Use zsh -lic for Rails commands with the installed Ruby. Tests must not send real messages, move money or depend on a running EP. Verify meaningful changes with Rails tests and RuboCop; check Zeitwerk after autoload changes.
- Use Playwright for browser checks. Update docs/requirements.md, roadmap.md, architecture.md, changelog.md and ui.md when features change.
- After code changes run `graphify update .` to refresh the ignored code graph. Commit verified changes; stage and commit separately with the workspace's required permissions.
