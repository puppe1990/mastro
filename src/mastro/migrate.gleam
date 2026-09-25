//// Migration runner.
////
//// Files are numbered `001_create_posts.sql` and every applied one is
//// recorded in `schema_migrations`, so running the same directory twice is
//// a no-op. A file may carry `-- up` and `-- down` sections; without them
//// the whole file is the `up` and the migration cannot be rolled back.
////
//// A `-- dev-only` marker keeps a migration — a demo user, sample rows —
//// out of production unless the operator asks for it explicitly.
////
//// ```gleam
//// migrate.run(execute, query_strings, "src/my_app/data/migrations", options)
//// ```

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub type Migration {
  Migration(
    name: String,
    filename: String,
    number: Int,
    up: String,
    down: Option(String),
    dev_only: Bool,
  )
}

/// Run a statement.
pub type Execute =
  fn(String) -> Result(Nil, String)

/// Run a query whose first column is text.
pub type Query =
  fn(String) -> Result(List(String), String)

/// What the runner needs to know that is not in the files.
pub type Options {
  Options(
    /// Unix seconds recorded as `applied_at`.
    now: Int,
    /// Production skips `-- dev-only` migrations unless `explicit`.
    production: Bool,
    /// The operator asked for this run, rather than a boot doing it.
    explicit: Bool,
  )
}

pub type Report {
  Report(applied: List(String), skipped: List(String))
}

pub type Status {
  Status(applied: List(String), pending: List(String))
}

/// The ledger. `name` is the filename, so a renamed file re-applies.
pub const schema_table_sql = "CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at INTEGER NOT NULL
)"

// -- Parsing ------------------------------------------------------------------

/// Split a file into its `up` and `down` halves.
///
/// `-- up` and `-- down` mark the sections. Without a marker the whole file
/// is the `up`. `-- dev-only` anywhere in the file marks it for development.
pub fn parse(filename: String, sql: String) -> Migration {
  let #(up, down, dev_only) = sections(sql)

  Migration(
    name: string.replace(filename, ".sql", ""),
    filename: filename,
    number: number_of(filename),
    up: up,
    down: down,
    dev_only: dev_only,
  )
}

type Section {
  Before
  Up
  Down
}

fn sections(sql: String) -> #(String, Option(String), Bool) {
  let #(up, down, _section, dev_only) =
    list.fold(string.split(sql, "\n"), #([], [], Before, False), step)

  #(plain(up), when_down(down), dev_only)
}

fn step(
  state: #(List(String), List(String), Section, Bool),
  raw: String,
) -> #(List(String), List(String), Section, Bool) {
  let #(up, down, section, dev_only) = state
  let line = string.trim(raw)

  case marker(line) {
    Some("up") -> #(up, down, Up, dev_only)
    Some("down") -> #(up, down, Down, dev_only)
    Some("dev-only") -> #(up, down, section, True)
    _ ->
      case section {
        Down -> #(up, [line, ..down], section, dev_only)
        _ -> #([line, ..up], down, section, dev_only)
      }
  }
}

fn when_down(lines: List(String)) -> Option(String) {
  case plain(lines) {
    "" -> None
    down -> Some(down)
  }
}

fn marker(line: String) -> Option(String) {
  case string.starts_with(line, "--") {
    True -> {
      let rest = string.trim(string.drop_start(line, 2))
      case rest {
        "up" | "down" | "dev-only" -> Some(rest)
        _ -> None
      }
    }
    False -> None
  }
}

fn number_of(filename: String) -> Int {
  case string.split(filename, "_") {
    [num, ..] ->
      case int.parse(num) {
        Ok(number) -> number
        Error(_) -> 0
      }
    _ -> 0
  }
}

// -- Reading ------------------------------------------------------------------

/// Every migration in the directory, in numeric order.
pub fn read_directory(dir: String) -> Result(List(Migration), String) {
  use files <- result.try(
    simplifile.read_directory(dir)
    |> result.replace_error("Could not read migrations directory: " <> dir),
  )

  use migrations <- result.try(
    files
    |> list.filter(fn(file) { string.ends_with(file, ".sql") })
    |> list.try_map(fn(filename) {
      use sql <- result.try(
        simplifile.read(dir <> "/" <> filename)
        |> result.replace_error("Could not read " <> filename),
      )
      Ok(parse(filename, sql))
    }),
  )

  Ok(list.sort(migrations, fn(a, b) { int.compare(a.number, b.number) }))
}

// -- Running ------------------------------------------------------------------

/// Apply every pending migration. Running twice applies nothing the second
/// time: the ledger already has the name.
pub fn run(
  execute: Execute,
  query: Query,
  dir: String,
  options: Options,
) -> Result(Report, String) {
  use _ <- result.try(execute(schema_table_sql))
  use applied <- result.try(applied_names(query))
  use migrations <- result.try(read_directory(dir))

  let selected =
    migrations
    |> list.filter(fn(migration) { !list.contains(applied, migration.filename) })
    |> list.map(fn(migration) { #(migration, runs(migration, options)) })

  let pending =
    selected
    |> list.filter(fn(entry) { entry.1 })
    |> list.map(fn(entry) { entry.0 })

  let skipped =
    selected
    |> list.filter(fn(entry) { !entry.1 })
    |> list.map(fn(entry) { { entry.0 }.filename })

  use _ <- result.try(apply_all(pending, execute, options.now))

  Ok(Report(
    applied: list.map(pending, fn(migration) { migration.filename }),
    skipped: skipped,
  ))
}

fn runs(migration: Migration, options: Options) -> Bool {
  case migration.dev_only {
    False -> True
    True -> !options.production || options.explicit
  }
}

fn apply_all(
  migrations: List(Migration),
  execute: Execute,
  now: Int,
) -> Result(Nil, String) {
  case migrations {
    [] -> Ok(Nil)
    [migration, ..rest] -> {
      io.println("  " <> migration.filename <> " ...")
      use _ <- result.try(
        execute(migration.up)
        |> result.map_error(fn(error) {
          "Migration " <> migration.filename <> " failed: " <> error
        }),
      )
      use _ <- result.try(execute(record_sql(migration, now)))
      io.println("  " <> migration.filename <> " ok")
      apply_all(rest, execute, now)
    }
  }
}

/// Revert the most recently applied migration: its `-- down` when it has
/// one, then the ledger row either way.
pub fn rollback(
  execute: Execute,
  query: Query,
  dir: String,
) -> Result(Option(String), String) {
  use _ <- result.try(execute(schema_table_sql))
  use applied <- result.try(applied_names(query))
  use migrations <- result.try(read_directory(dir))

  case list.last(applied) {
    Error(_) -> Ok(None)
    Ok(name) ->
      case list.find(migrations, fn(migration) { migration.filename == name }) {
        Error(_) -> {
          use _ <- result.try(execute(delete_sql(name)))
          Ok(Some(name))
        }
        Ok(migration) -> {
          use _ <- result.try(case migration.down {
            Some(down) ->
              execute(down)
              |> result.map_error(fn(error) {
                "Migration " <> migration.filename <> " failed: " <> error
              })
            None -> Ok(Nil)
          })
          use _ <- result.try(execute(delete_sql(name)))
          Ok(Some(name))
        }
      }
  }
}

/// What is applied and what is still pending, both in file order.
pub fn status(
  execute: Execute,
  query: Query,
  dir: String,
) -> Result(Status, String) {
  use _ <- result.try(execute(schema_table_sql))
  use applied <- result.try(applied_names(query))
  use migrations <- result.try(read_directory(dir))

  let filenames = list.map(migrations, fn(migration) { migration.filename })

  Ok(Status(
    applied: list.filter(filenames, fn(filename) {
      list.contains(applied, filename)
    }),
    pending: list.filter(filenames, fn(filename) {
      !list.contains(applied, filename)
    }),
  ))
}

// -- Ledger -------------------------------------------------------------------

fn applied_names(query: Query) -> Result(List(String), String) {
  query("SELECT name FROM schema_migrations ORDER BY applied_at, name")
}

fn record_sql(migration: Migration, now: Int) -> String {
  "INSERT INTO schema_migrations (name, applied_at) VALUES ('"
  <> literal(migration.filename)
  <> "', "
  <> int.to_string(now)
  <> ")"
}

fn delete_sql(name: String) -> String {
  "DELETE FROM schema_migrations WHERE name = '" <> literal(name) <> "'"
}

fn literal(value: String) -> String {
  string.replace(value, "'", "''")
}

// -- Helpers ------------------------------------------------------------------

fn plain(lines: List(String)) -> String {
  lines
  |> list.reverse
  |> string.join("\n")
  |> string.trim
}

/// The current unix time in seconds.
pub fn now() -> Int {
  system_time_seconds()
}

@external(erlang, "mastro_rate_limit_ffi", "system_time_seconds")
fn system_time_seconds() -> Int
