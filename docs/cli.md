# CLI Commands

The Mastro CLI is a code generator. Run it with:

```bash
gleam run -m mastro/cli -- <command>
```

Or set up an alias:

```bash
alias mastro='gleam run -m mastro/cli --'
```

## Commands

### `mastro new <name>`

Create a new Mastro project.

```bash
mastro new my_app
mastro new my_app --db postgres
mastro new my_app --db sqlite
mastro new path/to/my_app    # extracts "my_app" as package name
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--db postgres` | Add PostgreSQL (Pog) dependency and repo |
| `--db sqlite` | Add SQLite (Sqlight) dependency and repo |
| `--no-db` | No database (default) |

**Creates:** Full project with config, router, home handler, layout,
CSS, tests, and optionally a database repo.

---

### `mastro gen resource <name> <fields...>`

Generate a full CRUD resource.

```bash
mastro gen resource posts title:string body:text published:bool
mastro gen resource comments author:string body:text post_id:int
mastro gen resource products name:string price:float in_stock:bool

# JSON API mode (no views/forms, routes under /api/)
mastro gen resource posts title:string body:text --api
```

**Creates (HTML mode):**
- Handler (7 actions: index, show, new, create, edit, update, delete)
- Views (list, detail, form with proper field types)
- Form decoder with validation
- Domain type
- Database repo (Pog or Sqlight, auto-detected)
- SQL migration
- Tests

**Creates (API mode with `--api`):**
- Handler (5 actions: index, show, create, update, delete — JSON)
- Params type
- Domain type
- Database repo
- SQL migration
- Tests

**Patches:** `router.gleam` with RESTful routes (HTML: 7 routes,
API: 5 routes under `/api/` prefix).

**Field types:** See [Field Types](field-types.md).

**Naming:** The resource name should be plural (`posts`, not `post`).
The generator singularizes it for types (`Post`) and file names
(`post_handler.gleam`).

---

### `mastro gen page <name>`

Generate a simple page handler.

```bash
mastro gen page about
mastro gen page contact
mastro gen page pricing
```

**Creates:** Handler and test file.
**Patches:** `router.gleam` with a GET route.

---

### `mastro gen auth`

Generate a complete authentication system.

```bash
mastro gen auth
```

**Creates:** 9 files — user domain, user repo, auth handler, auth
views, auth form, auth middleware, migration, tests.

**Patches:** `router.gleam` with 5 auth routes.

See [Authentication](authentication.md) for details.

---

### `mastro gen island <name>`

Generate a Lustre interactive island.

```bash
mastro gen island counter
mastro gen island search
```

**Creates:**
- Island module (Lustre client-side app with init/update/view)
- Embed helper (server-side mount point and script tag)

See [Lustre Integration](lustre-integration.md) for details.

---

### `mastro gen live <name>`

Generate a Lustre server component with WebSocket transport.

```bash
mastro gen live dashboard
mastro gen live chat
```

**Creates:**
- Server component (Lustre app with init/update/view running on server)
- WebSocket socket module (transport scaffold with TODO instructions)
- Live handler (HTML page that connects via WebSocket)

**Patches:** `router.gleam` with a GET route for the live page.

The server component runs on the BEAM. DOM patches are sent to the
browser over WebSocket. See [Lustre Integration](lustre-integration.md).

---

### `mastro gen migration <name>`

Generate an empty SQL migration file.

```bash
mastro gen migration add_email_to_posts
mastro gen migration create_comments
```

**Creates:** Timestamped SQL file in `data/migrations/`.

---

### `mastro gen component <stem> [--list] [--dry-run]`

Seed an app-owned override for a shipped kit component, so the app restyles
the real contract instead of recreating it. In the Lustre view layer an
override is a module registered with `view.with_component` (ADR 0001).

```bash
mastro gen component --list          # print the overridable stems
mastro gen component locale-toggle   # seed web/components/locale_toggle.gleam
mastro gen component card --dry-run  # print the path, write nothing
```

**Creates:** `src/<app>/web/components/<stem>.gleam` with the
`(attrs, inner) -> Element` shape.

---

### `mastro destroy <kind> <name> [--dry-run]`

Remove generated files and undo the router patches.

```bash
mastro destroy resource posts
mastro destroy handler about
mastro destroy model post
mastro destroy migration add_email_to_posts
mastro destroy auth
mastro destroy resource posts --dry-run
```

- `resource` removes the handler/views/form/domain/repo/test and its
  `create_` migration, and unroutes it.
- `handler` removes the handler and its test.
- `model` removes the domain type and repo.
- `migration` deletes `*_<name>.sql` only — it never touches the
  `schema_migrations` ledger.
- `auth` removes the auth modules and unroutes them.
- `--dry-run` prints every change without writing.

---

### `mastro routes [--verbose]`

Print the route table from `router.gleam`.

```bash
mastro routes
mastro routes --verbose
```

**Output:**

```
GET     /                   home_handler.index
GET     /posts              post_handler.index
GET     /posts/new          post_handler.new
POST    /posts              post_handler.create
GET     /posts/:id          post_handler.show
```

`--verbose` adds the middleware stack and a static warning when two routes
can match the same method and path shape:

```
Middleware: method_override -> dev_log.request_log -> dev_error.rescue -> security.headers -> serve_static -> csrf.issue
warning: GET /posts/new may shadow GET /posts/:id
```

---

### `mastro migrate`

Run pending database migrations.

```bash
mastro migrate
```

On first run, generates a `src/<app>/migrate.gleam` module that
connects to the database and runs pending SQL files. Then executes it.

Requires a database (`--db postgres` or `--db sqlite`).

---

### `mastro db`

Database commands, answered by the generated module.

```bash
mastro db status            # list applied and pending migrations
mastro db rollback          # revert the most recent migration
mastro db prune-sessions    # delete expired sessions
mastro db seed              # run the project seeds
mastro db seed --list       # list the public helpers in the seed module
```

`status`, `rollback` and `prune-sessions` need a database; `seed` reuses
the seed module, creating it on first run.

---

### `mastro jobs`

Run and inspect the job queue.

```bash
mastro jobs work --queues send-email --concurrency 4
mastro jobs status
mastro jobs retry 42
mastro jobs discard 42
mastro jobs prune
```

On first run, generates a `src/<app>/jobs.gleam` worker that shares the
app's database, then runs it. `work` drains the queue and requeues what a
dead worker left behind.

---

### `mastro pwa [--bump] [--force]`

Install the PWA assets: `amarra.js`, `manifest.webmanifest`, `sw.js`, the
placeholder icons and `og.png`.

```bash
mastro pwa
mastro pwa --bump
mastro pwa --force
```

- `--bump` increments `CACHE_VERSION` in `sw.js`.
- `--force` resets the brand and the cache version.
- Without `--force`, existing files are preserved.

See [PWA & mobile](pwa.md) for the manifest contract and `/health`.

---

### `mastro build`

Compile Lustre islands to JavaScript.

```bash
mastro build
```

Finds island modules in `web/islands/`, compiles them to JS, and
copies output to `priv/static/js/islands/`.

---

### `mastro dev`

Start the dev server with file watching.

```bash
mastro dev
```

Sets `APP_ENV=dev` and runs `gleam run`. If `fswatch` is installed,
watches `src/` for changes and auto-rebuilds + restarts.

```bash
mastro dev
```

Wraps `gleam run` with the dev environment variable set.

---

### `mastro doctor [--mobile]`

Check the app against the Amarra contract and print one line per check.
Exits `1` when anything fails.

```bash
mastro doctor
mastro doctor --mobile
```

Core checks: the mastro dependency, `priv/static/`, the layout rendering
`#amarra-main`, `priv/static/js/amarra.js`, `manifest.webmanifest`, the
service worker, the jobs dashboard and the icon/og placeholders.

`--mobile` adds the on-device checks: flash inside `#amarra-main`, no
`fonts.googleapis.com` in the source (blocked by the default CSP),
`amarra.js` served network-first in `sw.js`, the `#chat-messages`
container, and `GET /health` returning `lan_urls`.

```
mastro doctor
  [ok  ] dependency: gleam.toml depends on mastro
  [ok  ] static: priv/static/ exists
  [fail] amarra.js: priv/static/js/amarra.js is missing — run `mastro pwa` to install the default assets
  ...
  1 failed, 3 warning(s)
```

---

### `mastro console`

Open a REPL over the project.

```bash
mastro console
```

```
mastro> SELECT count(*) FROM users
mastro> history
  1  SELECT count(*) FROM users
mastro> !1
mastro> exit
```

Commands: `help`, `history`, `!N` (re-run entry N), `!!` (re-run the last
command), `exit`/`quit`. The `store`, `cfg` and `db` bindings are in scope.
The line handling lives in `mastro/console` and is pure, so it is tested
without a terminal.

---

### `mastro link [path] [--unlink]`

Point `gleam.toml` at a local checkout of the framework for development.

```bash
mastro link ../mastro
mastro link --unlink
```

Writes `mastro = { path = "../mastro" }`. This is local-only — do not
commit it; `--unlink` restores the published version constraint.

---

### `mastro upgrade [version] [--dry-run]`

Bump the mastro constraint, print the migration steps, and run
`mastro doctor`.

```bash
mastro upgrade
mastro upgrade 0.3.0
mastro upgrade --dry-run
```

`--dry-run` reports the change and the steps without writing.

---

### `mastro help`

Show the help message with all commands.

```bash
mastro help
mastro --help
mastro -h
```

---

### `mastro version`

Print the version.

```bash
mastro version
mastro --version
```
