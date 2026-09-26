# Contributing to Mastro

Thanks for your interest in contributing to Mastro.

## Setup

```bash
git clone https://github.com/puppe1990/mastro.git
cd mastro

# Install mise if you do not have it (https://mise.jdx.dev)
#   brew install mise        # or: curl https://mise.run | sh
# Install toolchain (Gleam 1.14, Erlang 27, rebar3)
# With mise active, `gleam` inside this repo is the pinned 1.14 — the same
# version CI uses, so `gleam format --check` agrees with CI.
mise install

# Build
gleam build

# Run tests (288 tests, headless)
gleam test

# Format
gleam format
```

## Before submitting

```bash
gleam format --check
gleam build
gleam test
```

All three must pass. There are no exceptions.

## Project structure

```
src/
  mastro.gleam              ← library entry point
  mastro/
    validate.gleam           ← validation helpers
    flash.gleam              ← flash message helpers
    migrate.gleam            ← migration runner
    testing.gleam            ← test helpers
    cli.gleam                ← CLI entry point
    cli/
      new.gleam              ← mastro new
      gen/
        page.gleam           ← gen page
        resource.gleam       ← gen resource (orchestration)
        resource_*.gleam     ← the templates gen resource writes
        auth.gleam           ← gen auth (orchestration)
        auth_*.gleam         ← the auth templates
        live.gleam           ← gen live
        island.gleam         ← gen island
        migration.gleam      ← gen migration
        router.gleam         ← router.gleam patches every generator uses
        fields.gleam         ← field type parsing and SQL/Gleam mapping
      templates.gleam        ← file content templates
      routes.gleam           ← mastro routes
      build.gleam            ← mastro build (island JS)
      dev.gleam              ← mastro dev
      migrate_cmd.gleam      ← mastro migrate
      project.gleam          ← gleam.toml reader
      format.gleam           ← post-generation formatting
      types.gleam             ← shared types (DbChoice)

test/
  mastro_test.gleam         ← unit tests (validation)
  mastro/cli/
    gen_test.gleam           ← integration tests (generators)

docs/                        ← user documentation
examples/
  blog/                      ← Postgres example
  tasks_app/                 ← SQLite example
```

## How generators work

1. Each command has a module in `src/mastro/cli/gen/` that writes its files
   via `simplifile`; the content comes from that module's templates or from
   `templates.gleam`
2. Router patching (`src/mastro/cli/gen/router.gleam`) finds the `_, _ ->`
   catch-all and inserts routes before it
3. `gleam format` runs on all generated `.gleam` files automatically

## Adding a new generator

1. Add the module under `src/mastro/cli/gen/`, templates included
2. Add the command match in `cli.gleam`
3. Add an integration test in `test/mastro/cli/gen_test.gleam`
4. Update `docs/cli.md`

## Adding a new field type

1. Add the mapping in `src/mastro/cli/gen/fields.gleam` — `to_gleam_type`,
   `to_sql_type`, `to_sql_type_sqlite` and `form_default_value`
2. Handle in form view rendering (the `form_field_elements` builder)
3. Handle in `from_form_data` (the form decoder)
4. Update `docs/field-types.md`

## Conventions

- Generated code must pass `gleam format --check`
- Generated code must compile with zero warnings
- No framework abstractions — generated code uses Wisp/Lustre directly
- Domain types have zero framework imports
- Tests use `gleeunit` and `should`

## Reporting issues

- Use [GitHub Issues](https://github.com/puppe1990/mastro/issues)
- Include the Gleam version (`gleam --version`)
- Include the command that failed and the full error output
- If a generated file is wrong, include the generated file content

## License

By contributing, you agree that your contributions will be licensed
under the MIT License.
