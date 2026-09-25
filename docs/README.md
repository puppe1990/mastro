# Mastro Documentation

## Getting Started

- [Installation](installation.md) — install Mastro and create your first project
- [Tutorial: Build a Blog](tutorial.md) — step-by-step guide from `mastro new` to working app

## Guides

- [Project Structure](project-structure.md) — directory layout and conventions
- [Routing](routing.md) — how routes work, adding routes, route parameters
- [Handlers](handlers.md) — request handling, responses, middleware
- [Views & Templates](views.md) — Lustre HTML, layouts, components
- [Forms & Validation](forms.md) — form decoding, validation helpers, error display
- [Database](database.md) — Postgres and SQLite setup, repos, migrations
- [Authentication](authentication.md) — generated auth system, sessions, middleware
- [Sessions](sessions.md) — persistent sessions, rotation, pruning
- [Jobs](jobs.md) — the persistent queue, workers, retries and the dashboard
- [CSRF Protection](csrf.md) — double-submit tokens in forms, headers and Drive
- [Security Headers](security.md) — response hardening, the production gate, client address
- [Testing](testing.md) — test helpers, writing handler tests
- [Deployment](deployment.md) — building for production, environment config

## Reference

- [CLI Commands](cli.md) — all `mastro` commands and flags
- [Configuration](configuration.md) — config.gleam, environment variables
- [Field Types](field-types.md) — types available for `gen resource`

## Architecture

- [ADR 0001 — View layer](adr/0001-view-layer.md) — Lustre nativo vs templates HTML em runtime (aceito)
- [Lustre Integration](lustre-integration.md) — interactive islands and server components
- [Golden Path](GOLDEN_PATH.md) — original design spec (internal)
