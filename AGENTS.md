# AGENTS.md

Mastro — a convention-first web framework for Gleam (BEAM only). One Gleam package:
the library lives in `src/mastro/`, the CLI code generator in `src/mastro/cli/`.

## Commands

- Setup: Gleam 1.14+ and Erlang/OTP 27+ (`mise install` where mise is available)
- Test: `gleam test` — 285 tests, headless, no database or network required
- Test (browser JS): `npm test`
- Build: `gleam build`
- Format: `gleam format`, verify with `gleam format --check`
- Docs: `gleam docs build`
- Full CI locally: `gleam format --check && gleam build && gleam test && npm test && gleam docs build`
- Run the CLI: `gleam run -m mastro/cli -- <command>`
- Wrapper script: `./bin/build-cli.sh` then `./mastro <command>`
- Throwaway app: `mise run cli:new` (creates `test_app/`), remove with `mise run cli:clean`

## Structure

- `src/mastro/` — library: `validate`, `flash`, `migrate`, `session`, `csrf`, `jobs`, `kit`, `telemetry`, …
- `src/mastro/cli/` — one module per CLI subcommand (`gen`, `jobs_cmd`, `routes`, `new`, `destroy`, …)
- `src/mastro/cli.gleam` — entry point: argv → subcommand dispatch, prints `--help`
- `src/mastro/cli/templates.gleam` — file contents written by the generators (plain strings)
- `priv/static/js/` — browser JS and its `*.test.mjs`
- `test/` — mirrors `src/`: `src/mastro/jobs.gleam` ↔ `test/mastro/jobs_test.gleam`
- `docs/` — user docs; `docs/adr/` — decisions; `.claude/rules/` — architecture and convention detail
- `examples/blog` (Postgres) and `examples/tasks_app` (SQLite) — real generated apps
- `build/` and `test_app/` are generated — never edit them

## Conventions

- Gleam 1.14+, 2-space indent; `gleam format` is the authority, never hand-align.
- Import order: stdlib → external (`wisp`, `lustre`, `simplifile`) → internal (`mastro/...`).
- Explicit types on every public boundary.
- `let assert` only in `main()` and tests; library code returns `Result(_, _)`.
- Errors carry the offending value, not just "invalid input".
- Handlers: `fn(Request, Context) -> Response`; route params come last as `String`.
- Views return `Element(Nil)`, layouts return `String`, domain modules import zero frameworks.
- Generated code calls Wisp/Lustre directly — no framework abstraction layer.

## Rules

- Keep files under 500 lines; split by responsibility before adding logic.
- Keep functions 4–20 lines, one job each.
- Names must be grep-unique; no `util`, `helper` or `manager` as primary names.
- Max 2 nesting levels; prefer early returns.
- Keep WHY comments and provenance (issue numbers, ADRs); delete only obvious noise.
- Generated code must compile with zero warnings and pass `gleam format --check`.
- Reuse the existing `mastro/rate_limit` and `mastro/jobs` retry policy; do not invent new retry, breaker or fallback behaviour.
- Toolchain drift: on a Gleam newer than the pinned 1.14 the formatter wraps signatures differently, so `gleam format --check` fails on files CI accepts. Do not reformat those files in unrelated changes.

## Testing

- New behaviour needs a test; every bugfix needs a regression test.
- `gleam test` stays headless: in-memory SQLite and stubs, no external services.
- Generator changes: cover in `test/mastro/cli/gen_test.gleam`; CLI/route parity in `test/mastro/cli/parity_test.gleam`.
- A generator change is done only when the generated project compiles and passes `gleam format --check`.

## Boundaries

- Ask before: publishing to Hex, tagging a release, force-push, editing `.github/workflows/`.
- Do not edit: `build/`, `test_app/`, vendored assets under `priv/`.
- `docs/` is the source of truth for user-facing behaviour — update the matching page when behaviour changes.
