# AGENTS.md

## Environment/runtime

- Run Rails commands with zsh -lic 'cd <project path> && <command>' to load mise Ruby 3.4.4.
- If the prompt mentions 'migrate the', 'migration of', or like meaning word sets, it is a signal to you, to go look in `../calc/*`, or `../kalkulation_rails/*`, or `../../mortimer/goldbox/app/*` for models, controllers, javascripts, services, more and pull in those artifacts

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)

## Browser access

- When requiring access to a browser **ALWAYS** use the Playwright MCP
- Once done using the browser access **ALWAYS** remember to remove any Playwright hooks blocking access from development/production js

## Workflow: Plan-Do-Check-Act

You must follow this cycle for every task:

1. **Plan**: Outline the changes and files to be modified.
2. **Do**: Implement the code changes.
3. **Check**: **MANDATORY** - Run the test suite to verify changes.
   - Command: `rails test` (or your specific test command)
   - If tests fail, you must fix the code before proceeding.
4. **Act**: Finalize the changes and summarize the outcome.

These steps are detailed further here:

1. (PLAN) Start by reasoning about the prompt in the context of the available code and consider whether it is
   1. a bug in 1-3 files that needs fixing
   2. a change request that requires a small or larger rewrite of controllers, models, and/or components/views
   3. an epic/feature - typically a new provision, entity, model(s), etc
   4. a user story building up a number of epics/features
2. (PLAN) Always plan what artifacts you intend to add/edit/delete to solve the prompt
3. (DO) Depending on the nature and size of the plan - your step 1 - divide the plan into testable chunks
4. (DO/CHECK) Chunks should have 5 steps
   1. Create a test that touches on some of the issue in the chunk
   2. Run this test and verify that it fails
   3. Write code that mitigates it
   4. Run the test again and verify that it now is 'green' - ie that it does not fail
   5. Run `bundle exec rubocop -a` when tests are green
   6. If the test still fails, or rubocop cannot mitigate automatically, loop back to #3
5. (ACT) When you are done and all tests are green then commit with a one line resume of the prompt/change
6. (ACT) [as stated above] After modifying code files, run `graphify update .` to keep the graph current (AST-only, no API cost)
7. (ACT) Finally use the changes to update the documentation depending upon
   1. bugs - no changes to documentation
   2. change requests - be careful to do proper update as documentation and code otherwise will drift
   3. epic/feature - add new paragraphs, even chapters perhaps
   4. user story - chapters, even entire sections because user stories are usually not in the documentation already

## Documentation

1. The system architect will posit requirements and your job is to rewrite this into brief abstracts into `docs/requirements.md`. The system architect may edit this file themselves!
2. You must boil these abstracts down into 1-line roadmap entries and persist them into `docs/roadmap.md`
3. Working on this roadmap.md (perhaps prioritized by the Product Owner) from the top, you will use the Development Process (perhaps in collaboration with a developer) described above to reach at a set of architecture decisions that you must write to `docs/architecture.md` - and implement.
4. After implementation is GREEN always document changes to the `docs/changelog.md`
5. Finish up by documenting system features, logic, navigation, platforms, api, more in `docs/ui.md`

## Implementation guardrails

1. Always build out UI using Phlex components - if html.erb files is required, ask for acceptance.
2. Controllers must set `layout false` because Phlex renders a layout in an around_template action
3. Always create database migrations with `bin/rails generate migration`

## Command exemptions

1. stop trying git commit sandboxed first and go straight to escalated `git add` / `git commit -m` when .git writes are involved. It is allowed in the .codex/rules already.
2. do not run `git add` and `git commit` commands as one command. Split them into separate escalated commands.

## Database-backed test commands

- PostgreSQL is available for development and test.
- Run Rails tests with local database access:
  `zsh -lic 'cd /Users/walther/Deling/Walther/src/karl_a/carla && PARALLEL_WORKERS=1 rails test'`
- Database-backed Rails commands may require elevated execution permissions.
