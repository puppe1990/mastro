# Mastro

> **A convention-first web framework for Gleam. Productive like Phoenix, explicit like Gleam, composable with Wisp and Lustre.**

Mastro gives Gleam developers Phoenix-like coherence and Rails-like convention without macros, magic, or hidden runtime tricks. It is a CLI code generator that produces plain Gleam code, plus a small library of helpers for validation, flash messages, migrations, and testing.

**Agent rules, commands and structure live in [../AGENTS.md](../AGENTS.md) — read it first.** This file covers philosophy and architecture; `.claude/rules/` holds the detailed conventions.

## Philosophy

1. **Conventions over assembly** — One obvious way to structure an app. Default project layout, naming rules, routing shape.
2. **Generated code is your code** — The CLI produces plain Gleam files you own and modify. No "framework code" vs "your code" distinction.
3. **No magic, no macros** — Gleam intentionally lacks metaprogramming. Mastro respects that. Routing is pattern matching. Views are functions. Validation is functions.
4. **Wisp + Lustre, not NIH** — Build on the ecosystem, don't replace it. Wisp handles HTTP. Lustre handles HTML. Mastro adds the conventions and generators.
5. **Boring where boring is good** — CRUD, forms, validation, sessions, layouts. Get this right before chasing real-time cleverness.

**Before adding anything, ask:**
- Does this make a new Gleam developer more productive in their first hour?
- Is this convention or configuration? Prefer convention.
- Could this be generated code instead of framework code?

## Architecture

One Gleam package, two deliverables:

```
mastro/
├── src/mastro/          ← Library: validate, flash, migrate, session, csrf, jobs, rate_limit, kit, telemetry
├── src/mastro/cli/      ← CLI: code generators, project scaffolding
├── test/                ← mirrors src/
├── docs/                ← user docs, ADRs, golden path
├── examples/            ← blog (Postgres), tasks_app (SQLite)
└── priv/static/js/      ← browser JS and its tests
```

### Two Deliverables

**Library (`src/mastro/`, re-exported by `src/mastro.gleam`)** — imported by generated projects. Contains:
- Validation helpers (required, min_length, max_length, format, etc.)
- Flash message helpers (signed cookies)
- Session, CSRF, CORS, rate limiting, telemetry
- Job queue (`mastro/jobs`) and migration runner (SQL files, tracking table)
- Kit components, test helpers (request builders)
- Dev error page and dev logs

**CLI (`src/mastro/cli/`, entry point `src/mastro/cli.gleam`)** — development tool only, never an import of generated code at runtime:
- `mastro new` — scaffold a project
- `mastro gen page | resource | auth | migration | island | live | component`
- `mastro destroy` — remove generated files and patches
- `mastro migrate`, `mastro db`, `mastro seed` — database tasks
- `mastro jobs` — run and inspect the queue
- `mastro routes`, `mastro build`, `mastro dev`, `mastro doctor`, `mastro console`
- `mastro assets`, `mastro pwa`, `mastro link`, `mastro upgrade`

Full command list and flags: `docs/cli.md` and `mastro --help`.

Generated projects depend on the `mastro` package; in a local checkout, `mastro link <path/to/mastro>` points their `gleam.toml` at the source tree.

### Generated App Structure

```
my_app/
  src/
    my_app.gleam                    ← entry point
    my_app/
      config.gleam                  ← typed config, env-driven
      context.gleam                 ← shared Context (config + db)
      router.gleam                  ← all routes, pattern matched

      web/                          ← HTTP/UI layer
        handlers, views, forms,
        layouts, components, middleware, islands

      domain/                       ← business logic (no framework imports)

      data/                         ← persistence (repos, migrations)

  priv/static/                      ← CSS, JS, assets
  test/                             ← tests mirror src/ structure
```

### Dependency Flow

```
web/ → domain/     ✓
data/ → domain/    ✓
domain/ → web/     ✗ (never)
domain/ → data/    ✗ (never)
```

## Key Concepts

### Router

One file. Pattern matching on `wisp.path_segments(req)` and `req.method`. No DSL, no registration. Generators patch this file by inserting before the catch-all.

### Handlers

Plain functions: `fn(Request, Context) -> Response` or `fn(Request, Context, String) -> Response` for parameterized routes. No traits, no interfaces.

### Views

Lustre HTML functions for type-safe templating. Views produce `Element(Nil)`. Layouts wrap `Element(Nil) → String` via `element.to_document_string`.

### Forms

Typed decoders with validation. Two types per form: `PostForm` (display state for re-rendering) and `PostParams` (validated input). Errors are `List(#(String, String))`.

### Domain

Pure Gleam types. No framework imports. No database imports. Your business logic.

### Repos

Raw SQL via Pog (Postgres) or Sqlight (SQLite). Typed decoders. No ORM.

## Dependencies

Versions live in `gleam.toml` (framework) and `src/mastro/cli/templates.gleam` (generated projects).

**This package** — `gleam_stdlib`, `gleam_erlang`, `gleam_otp`, `gleam_http`, `gleam_json`, `wisp`, `lustre`, `glint`, `argv`, `tom`, `simplifile`, `exception`, `gleam_crypto`; dev: `gleeunit`.

**Injected into generated projects** — `mist` (HTTP server), `envoy` (dotenv), `wisp`, `lustre`, `gleam_json`, `mastro`, plus `pog` (Postgres) or `sqlight` (SQLite); dev: `gleeunit`.

## Rules

| File | Purpose |
|------|---------|
| [gleam-standards.md](rules/gleam-standards.md) | Gleam coding standards |
| [architecture.md](rules/architecture.md) | Architecture decisions and constraints |
| [conventions.md](rules/conventions.md) | Naming, structure, and generated code conventions |
| [workflow.md](rules/workflow.md) | Commands, testing, releases |

## Quick Reference

### Common Commands

See [../AGENTS.md](../AGENTS.md#commands) — single source of truth for commands.

### Key Files

| Path | Purpose |
|------|---------|
| `src/mastro.gleam` | Library entry point (re-exports) |
| `src/mastro/validate.gleam` | Validation helpers |
| `src/mastro/flash.gleam` | Flash message helpers |
| `src/mastro/migrate.gleam` | Migration runner |
| `src/mastro/jobs.gleam` | Job queue and retry policy |
| `src/mastro/testing.gleam` | Test helpers |
| `src/mastro/cli.gleam` | CLI entry point |
| `src/mastro/cli/gen/` | One module per generator (`resource.gleam` + `resource_*` templates, `auth.gleam` + `auth_*` templates, `page`, `migration`, `island`, `live`) |
| `src/mastro/cli/gen/router.gleam` | Every `router.gleam` patch (routes and imports) |
| `src/mastro/cli/gen/fields.gleam` | Field type parsing and the Gleam/SQL type mapping |
| `src/mastro/cli/templates.gleam` | File content templates |
| `docs/GOLDEN_PATH.md` | Golden path specification |
