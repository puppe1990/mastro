/// `mastro migrate` and the generated database module.
///
/// Creates `src/<app>/migrate.gleam`, which knows how to reach the project's
/// database and answers every `mastro db` subcommand, then runs it.
///
import gleam/io
import gleam/string
import mastro/cli/format
import mastro/cli/project
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

@external(erlang, "mastro_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

/// `mastro migrate`: apply the pending migrations.
pub fn run() {
  let app = project.app_name()
  let db = project.detect_db()

  case db {
    NoDb -> no_database()
    _ -> {
      case ensure_module(app, db) {
        False -> Nil
        True -> io.println("Running migrations...")
      }
      io.println(run_cmd("gleam run -m " <> app <> "/migrate"))
    }
  }
}

/// `mastro db <command>`: forward the arguments to the generated module.
pub fn run_command(app: String, db: DbChoice, args: List(String)) {
  let _ = ensure_module(app, db)

  let command = case args {
    [] -> "gleam run -m " <> app <> "/migrate"
    _ -> "gleam run -m " <> app <> "/migrate -- " <> string.join(args, " ")
  }

  io.println(run_cmd(command))
}

/// Write the database module when the project has none yet. Returns whether
/// it was created.
pub fn ensure_module(app: String, db: DbChoice) -> Bool {
  let path = "src/" <> app <> "/migrate.gleam"

  case simplifile.read(path) {
    Ok(_) -> False
    Error(_) -> {
      let content = case db {
        Postgres -> module_postgres(app)
        Sqlite -> module_sqlite(app)
        NoDb -> ""
      }

      let assert Ok(_) = simplifile.write(path, content)
      format.format_files([path])
      io.println("Created: " <> path)
      True
    }
  }
}

fn no_database() {
  io.println("No database configured.")
  io.println("Create a project with --db postgres or --db sqlite.")
}

fn header(app: String, driver: String) -> String {
  "// Database commands.
//
// Usage:
//   gleam run -m " <> app <> "/migrate                   # apply pending
//   gleam run -m " <> app <> "/migrate -- status
//   gleam run -m " <> app <> "/migrate -- rollback
//   gleam run -m " <> app <> "/migrate -- prune-sessions
//
import argv
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import " <> app <> "/config
import " <> app <> "/data/repo
import mastro/migrate
import mastro/session
import " <> driver <> "
import wisp

"
}

/// The commands every driver answers, once the connection has been settled.
fn helpers(app: String) -> String {
  "fn apply(
  execute: migrate.Execute,
  query: migrate.Query,
  dir: String,
  cfg: config.Config,
) -> Nil {
  case migrate.run(execute, query, dir, options(cfg)) {
    Ok(report) -> {
      case report.applied {
        [] -> io.println(\"Nothing to apply.\")
        applied ->
          io.println(
            \"Applied \"
            <> int.to_string(list.length(applied))
            <> \" migration(s).\",
          )
      }
      case report.skipped {
        [] -> Nil
        skipped -> io.println(\"Skipped (dev-only): \" <> string.join(skipped, \", \"))
      }
    }
    Error(error) -> io.println(\"Error: \" <> error)
  }
}

fn status(execute: migrate.Execute, query: migrate.Query, dir: String) -> Nil {
  case migrate.status(execute, query, dir) {
    Ok(report) -> {
      io.println(\"Applied:\")
      list.each(report.applied, fn(name) { io.println(\"  \" <> name) })
      io.println(\"Pending:\")
      list.each(report.pending, fn(name) { io.println(\"  \" <> name) })
    }
    Error(error) -> io.println(\"Error: \" <> error)
  }
}

fn rollback(execute: migrate.Execute, query: migrate.Query, dir: String) -> Nil {
  case migrate.rollback(execute, query, dir) {
    Ok(option.Some(name)) -> io.println(\"Rolled back \" <> name)
    Ok(option.None) -> io.println(\"Nothing to roll back.\")
    Error(error) -> io.println(\"Error: \" <> error)
  }
}

fn prune_sessions(execute: migrate.Execute) -> Nil {
  let sql =
    string.replace(session.prune_sql, \"?\", int.to_string(session.now()))

  case execute(sql) {
    Ok(_) -> io.println(\"Expired sessions pruned.\")
    Error(error) -> io.println(\"Error: \" <> error)
  }
}

fn name_decoder() -> decode.Decoder(String) {
  use name <- decode.field(0, decode.string)
  decode.success(name)
}

fn options(cfg: config.Config) -> migrate.Options {
  migrate.Options(
    now: session.now(),
    production: config.is_production(cfg),
    explicit: True,
  )
}
"
}

fn module_postgres(app: String) -> String {
  header(app, "pog") <> "pub fn main() {
  let cfg = config.load()
  let assert Ok(db) = repo.connect(cfg)
  let dir = \"src/" <> app <> "/data/migrations\"
  let execute = execute(db)
  let query = query_strings(db)

  case argv.load().arguments {
    [\"status\", ..] -> status(execute, query, dir)
    [\"rollback\", ..] -> rollback(execute, query, dir)
    [\"prune-sessions\", ..] -> prune_sessions(execute)
    _ -> apply(execute, query, dir, cfg)
  }
}

fn execute(db: pog.Connection) -> migrate.Execute {
  fn(sql) {
    pog.query(sql)
    |> pog.execute(db)
    |> result.replace(Nil)
    |> result.replace_error(\"query failed\")
  }
}

fn query_strings(db: pog.Connection) -> migrate.Query {
  fn(sql) {
    pog.query(sql)
    |> pog.returning(name_decoder())
    |> pog.execute(db)
    |> result.map(fn(returned) { returned.rows })
    |> result.replace_error(\"query failed\")
  }
}

" <> helpers(app)
}

fn module_sqlite(app: String) -> String {
  header(app, "sqlight") <> "pub fn main() {
  let cfg = config.load()
  let dir = \"src/" <> app <> "/data/migrations\"

  use db <- sqlight.with_connection(repo.database_path(cfg))

  let execute = execute(db)
  let query = query_strings(db)

  case argv.load().arguments {
    [\"status\", ..] -> status(execute, query, dir)
    [\"rollback\", ..] -> rollback(execute, query, dir)
    [\"prune-sessions\", ..] -> prune_sessions(execute)
    _ -> apply(execute, query, dir, cfg)
  }
}

fn execute(db: sqlight.Connection) -> migrate.Execute {
  fn(sql) {
    sqlight.exec(sql, db)
    |> result.replace(Nil)
    |> result.replace_error(\"query failed\")
  }
}

fn query_strings(db: sqlight.Connection) -> migrate.Query {
  fn(sql) {
    sqlight.query(sql, on: db, with: [], expecting: name_decoder())
    |> result.replace_error(\"query failed\")
  }
}

" <> helpers(app)
}
