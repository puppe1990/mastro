# Workflow

Commands, processes, and common tasks for working on Mastro.

---

## Development Environment

### Prerequisites

- Gleam 1.14+ (pinned by `mise.toml`)
- Erlang/OTP 27+
- rebar3
- Node 22 (browser JS tests)

### Setup

```bash
mise install   # where mise is available
gleam build
gleam test
```

---

## Common Commands

### Building

```bash
gleam build    # build the package
gleam check    # type-check without a full build
```

### Testing

```bash
gleam test     # all Gleam tests — headless, in-memory SQLite, no external services
npm test       # browser JS tests (node --test, priv/static/js/*.test.mjs)
```

`gleeunit` runs every `*_test` function under `test/`; there are no filter
flags. To verify a single module, read its `test/mastro/<module>_test.gleam`
and run the full suite.

### Formatting

```bash
gleam format         # format all code
gleam format --check # verify (what CI runs)
```

### Documentation

```bash
gleam docs build
gleam docs build --open
```

### Full CI locally

```bash
gleam format --check && gleam build && gleam test && npm test && gleam docs build
```

This mirrors `.github/workflows/ci.yml` exactly.

---

## Working on the CLI

### Running CLI Commands Locally

The CLI is the `mastro/cli` module of this package:

```bash
# From the repo root
gleam run -m mastro/cli -- new test_app --db postgres

cd test_app
gleam run -m mastro/cli -- gen resource posts title:string body:text published:bool
gleam run -m mastro/cli -- gen page about
```

`./bin/build-cli.sh` creates a `./mastro` wrapper that delegates to
`gleam run -m mastro/cli -- "$@"`.

`test_app/` is gitignored; `mise run cli:new` and `mise run cli:clean` wrap
creating and removing it.

### Testing Generated Output

After running a generator, verify:

1. `gleam build` compiles without errors
2. `gleam test` passes
3. Generated files follow conventions (`rules/conventions.md`)
4. Router patch is correct (routes before the catch-all)
5. `gleam format --check` passes on generated code

---

## Working on the Library

Tests live under `test/` and mirror the module path:

| Module | Test |
|--------|------|
| `src/mastro/validate.gleam` | `test/mastro_test.gleam` |
| `src/mastro/migrate.gleam` | `test/mastro/migrate_test.gleam` |
| `src/mastro/jobs.gleam` | `test/mastro/jobs_test.gleam` |
| `src/mastro/session.gleam` | `test/mastro/session_test.gleam` |
| `src/mastro/csrf.gleam` | `test/mastro/csrf_test.gleam` |
| `src/mastro/security.gleam` | `test/mastro/security_test.gleam` |

New behaviour needs a test; every bugfix needs a regression test.

---

## Git Workflow

### Branch Naming

```
feature/gen-resource-command
feature/validation-helpers
fix/router-patch-ordering
docs/golden-path-update
```

### Commit Messages

```
feat(cli): add gen resource command

Generates handler, views, form, domain type, repo, and migration
for a full CRUD resource. Patches router with RESTful routes.
```

```
feat(lib): add validation helpers

Required, min_length, max_length, format, inclusion validators.
All composable, return List(#(String, String)) errors.
```

### Pre-commit Checklist

```bash
gleam format
gleam build
gleam test
```

---

## Release Process

### Version Bump

1. Update `version` in `gleam.toml`
2. Update the version string printed by `mastro version` in `src/mastro/cli.gleam` (it is hardcoded)
3. Commit: `chore: bump version to X.Y.Z`
4. Tag: `git tag vX.Y.Z`
5. Push: `git push && git push --tags`

### Publishing to Hex

One package, at the repository root:

```bash
gleam publish
```

---

## CI

`.github/workflows/ci.yml` is the only workflow. On push to `main` and on
pull requests it runs:

```bash
gleam format --check
gleam build
gleam test
npm test
gleam docs build
```

### Toolchain drift (known trap)

CI and `mise.toml` pin Gleam 1.14. A newer local Gleam wraps function
signatures the older one keeps on one line, so `gleam format --check` fails
locally on files CI accepts. As of Gleam 1.18 those are:
`src/mastro/csrf.gleam`, `src/mastro/doctor.gleam`, `src/mastro/jobs.gleam`,
`src/mastro/kit.gleam` and
`examples/tasks_app/src/tasks_app/data/task_repo.gleam`. Do not reformat them
from a newer toolchain in unrelated changes.
