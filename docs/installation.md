# Installation

## Prerequisites

- **Gleam** 1.14 or later — [gleam.run/getting-started](https://gleam.run/getting-started/)
- **Erlang/OTP** 27 or later
- **rebar3** (installed automatically with most Erlang distributions)

Optional:
- **PostgreSQL** — if using `--db postgres`
- **SQLite** — if using `--db sqlite` (usually pre-installed on macOS/Linux)

### Using mise (recommended)

If you use [mise](https://mise.jdx.dev/) for toolchain management:

```bash
mise use gleam@1.14
mise use erlang@27
mise use rebar@3
```

## Get the CLI

Mastro is **not published to Hex yet**, so `gleam add mastro` does not
resolve. Use a local checkout:

```bash
git clone https://github.com/puppe1990/mastro.git
cd mastro
gleam run -m mastro/cli -- version   # mastro 0.2.0
```

Build a `mastro` wrapper so you can drop the `gleam run` prefix, and put
the checkout on your `PATH` to call it from anywhere:

```bash
./bin/build-cli.sh        # creates ./mastro
export PATH="$PWD:$PATH"
mastro help
```

The wrapper runs the compiled CLI from the checkout while keeping your
current directory: `mastro new my_app` creates the app where you are, and
`mastro gen resource ...` inside an app acts on that app. Only `erl` is
needed at run time, not `gleam`.

## Create your first project

Generated apps depend on the framework source, so point them at the
checkout with `mastro link`:

```bash
# from the parent of the mastro checkout
mastro new my_app --db sqlite
cd my_app
mastro link ../mastro      # writes mastro = { path = "../mastro" }
gleam run
```

Visit http://localhost:4000 — you should see the welcome page.

`mastro link` is local-only: do not commit it. `mastro link --unlink`
restores the version constraint once mastro is published:

```toml
mastro = ">= 0.1.0 and < 1.0.0"
```

### With a database

```bash
# PostgreSQL
mastro new my_app --db postgres

# SQLite
mastro new my_app --db sqlite
```

### Without a database

```bash
mastro new my_app
```

This is the default. You can add a database later by manually adding
`pog` or `sqlight` to your `gleam.toml` dependencies.

## Verify your setup

```bash
cd my_app
gleam build    # Should compile without errors
gleam test     # Should pass
gleam run      # Should start on http://localhost:4000
```

## Next steps

- [Tutorial: Build a Blog](tutorial.md) — 10-minute walkthrough
- [Project Structure](project-structure.md) — understand the directory layout
- [CLI Commands](cli.md) — see all available commands
