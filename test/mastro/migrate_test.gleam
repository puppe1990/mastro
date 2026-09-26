import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import gleeunit/should
import mastro/migrate
import simplifile

// -- A fake database ----------------------------------------------------------

type Fake {
  Fake(statements: List(String), applied: List(String))
}

type FakeMessage {
  Execute(String, process.Subject(Result(Nil, String)))
  Query(String, process.Subject(Result(List(String), String)))
  Log(process.Subject(List(String)))
}

fn database() -> process.Subject(FakeMessage) {
  let assert Ok(started) =
    actor.new(Fake(statements: [], applied: []))
    |> actor.on_message(handle)
    |> actor.start

  started.data
}

fn handle(state: Fake, message: FakeMessage) -> actor.Next(Fake, FakeMessage) {
  case message {
    Execute(statement, reply) -> {
      process.send(reply, Ok(Nil))
      actor.continue(Fake(
        statements: [statement, ..state.statements],
        applied: apply_to_ledger(state.applied, statement),
      ))
    }

    Query(_statement, reply) -> {
      process.send(reply, Ok(state.applied))
      actor.continue(state)
    }

    Log(reply) -> {
      process.send(reply, list.reverse(state.statements))
      actor.continue(state)
    }
  }
}

fn execute(database: process.Subject(FakeMessage)) -> migrate.Execute {
  fn(statement) {
    process.call_forever(database, fn(reply) { Execute(statement, reply) })
  }
}

fn query(database: process.Subject(FakeMessage)) -> migrate.Query {
  fn(statement) {
    process.call_forever(database, fn(reply) { Query(statement, reply) })
  }
}

fn statements(database: process.Subject(FakeMessage)) -> List(String) {
  process.call_forever(database, fn(reply) { Log(reply) })
}

/// Mimic the ledger: an insert adds a name, a delete removes one.
fn apply_to_ledger(applied: List(String), statement: String) -> List(String) {
  case inserted_name(statement) {
    Some(name) -> list.append(applied, [name])
    None ->
      case deleted_name(statement) {
        Some(name) -> list.filter(applied, fn(applied) { applied != name })
        None -> applied
      }
  }
}

fn deleted_name(statement: String) -> Option(String) {
  case string.split(statement, "WHERE name = '") {
    [_, rest] ->
      case string.split(rest, "'") {
        [name, _] -> Some(name)
        _ -> None
      }
    _ -> None
  }
}

fn inserted_name(statement: String) -> Option(String) {
  case string.split(statement, "VALUES ('") {
    [_, rest] ->
      case string.split(rest, "',") {
        [name, _] -> Some(name)
        _ -> None
      }
    _ -> None
  }
}

// -- Fixtures -----------------------------------------------------------------

fn in_temp_dir(name: String, f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/mastro_migrate_" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  f(dir)
  let _ = simplifile.delete_all([dir])
  Nil
}

fn write(dir: String, filename: String, content: String) -> Nil {
  let assert Ok(_) = simplifile.write(dir <> "/" <> filename, content)
  Nil
}

fn options(production: Bool, explicit: Bool) -> migrate.Options {
  migrate.Options(now: 1000, production: production, explicit: explicit)
}

const posts_sql = "-- up
CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT);
-- down
DROP TABLE posts;"

fn two_migrations(dir: String) -> Nil {
  write(dir, "001_create_posts.sql", posts_sql)
  write(
    dir,
    "002_add_published.sql",
    "-- up
ALTER TABLE posts ADD COLUMN published INTEGER NOT NULL DEFAULT 0;
-- down
ALTER TABLE posts DROP COLUMN published;",
  )
}

fn last_statement(database: process.Subject(FakeMessage)) -> String {
  case list.last(statements(database)) {
    Ok(statement) -> statement
    Error(_) -> ""
  }
}

// -- Parsing ------------------------------------------------------------------

pub fn parse_reads_both_sections_test() {
  let migration = migrate.parse("001_create_posts.sql", posts_sql)

  should.equal(migration.name, "001_create_posts")
  should.equal(migration.number, 1)
  should.equal(
    migration.up,
    "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT);",
  )
  should.equal(migration.down, Some("DROP TABLE posts;"))
  should.be_false(migration.dev_only)
}

pub fn parse_without_markers_makes_the_whole_file_the_up_test() {
  let migration =
    migrate.parse("003_seed.sql", "INSERT INTO posts (title) VALUES ('a');")

  should.equal(migration.up, "INSERT INTO posts (title) VALUES ('a');")
  should.equal(migration.down, None)
}

pub fn parse_reads_the_dev_only_marker_test() {
  let migration =
    migrate.parse(
      "004_demo_user.sql",
      "-- dev-only
-- up
INSERT INTO users (email) VALUES ('demo@example.com');",
    )

  should.be_true(migration.dev_only)
  should.equal(
    migration.up,
    "INSERT INTO users (email) VALUES ('demo@example.com');",
  )
}

pub fn a_missing_migrations_dir_is_not_an_error_test() {
  // A scaffold that has generated nothing yet has no migrations directory,
  // and `mastro migrate` should say so rather than fail.
  migrate.read_directory("/tmp/mastro_migrations_that_do_not_exist")
  |> should.equal(Ok([]))
}

pub fn migrations_are_read_in_numeric_order_test() {
  in_temp_dir("order", fn(dir) {
    write(dir, "010_ten.sql", "SELECT 10;")
    write(dir, "002_two.sql", "SELECT 2;")
    write(dir, "001_one.sql", "SELECT 1;")

    let assert Ok(migrations) = migrate.read_directory(dir)

    should.equal(list.map(migrations, fn(migration) { migration.filename }), [
      "001_one.sql",
      "002_two.sql",
      "010_ten.sql",
    ])
  })
}

// -- Running ------------------------------------------------------------------

pub fn running_twice_applies_nothing_the_second_time_test() {
  in_temp_dir("twice", fn(dir) {
    two_migrations(dir)
    let db = database()

    let assert Ok(first) =
      migrate.run(execute(db), query(db), dir, options(False, True))

    should.equal(first.applied, [
      "001_create_posts.sql",
      "002_add_published.sql",
    ])
    should.equal(first.skipped, [])

    let assert Ok(second) =
      migrate.run(execute(db), query(db), dir, options(False, True))

    should.equal(second.applied, [])
    should.equal(
      statements(db)
        |> list.filter(fn(statement) {
          string.contains(statement, "ALTER TABLE posts ADD COLUMN")
        })
        |> list.length,
      1,
    )
  })
}

pub fn the_ledger_records_when_a_migration_was_applied_test() {
  in_temp_dir("ledger", fn(dir) {
    two_migrations(dir)
    let db = database()
    let assert Ok(_) =
      migrate.run(execute(db), query(db), dir, options(False, True))

    should.be_true(
      list.any(statements(db), fn(statement) {
        string.contains(statement, "'001_create_posts.sql', 1000")
      }),
    )
  })
}

pub fn dev_only_migrations_skip_production_unless_explicit_test() {
  in_temp_dir("dev_only", fn(dir) {
    two_migrations(dir)
    write(
      dir,
      "003_demo_user.sql",
      "-- dev-only
INSERT INTO users (email) VALUES ('demo@example.com');",
    )

    let production = database()
    let assert Ok(report) =
      migrate.run(
        execute(production),
        query(production),
        dir,
        options(True, False),
      )

    should.equal(report.skipped, ["003_demo_user.sql"])
    should.equal(report.applied, [
      "001_create_posts.sql",
      "002_add_published.sql",
    ])

    let assert Ok(explicit_report) =
      migrate.run(
        execute(production),
        query(production),
        dir,
        options(True, True),
      )

    should.equal(explicit_report.applied, ["003_demo_user.sql"])
  })
}

// -- Status and rollback ------------------------------------------------------

pub fn status_lists_applied_and_pending_test() {
  in_temp_dir("status", fn(dir) {
    two_migrations(dir)
    write(dir, "003_later.sql", "SELECT 3;")
    let db = database()
    let assert Ok(_) =
      migrate.run(execute(db), query(db), dir, options(False, True))
    write(dir, "004_even_later.sql", "SELECT 4;")

    let assert Ok(status) = migrate.status(execute(db), query(db), dir)

    should.equal(status.applied, [
      "001_create_posts.sql",
      "002_add_published.sql",
      "003_later.sql",
    ])
    should.equal(status.pending, ["004_even_later.sql"])
  })
}

pub fn rollback_reverts_the_schema_and_the_ledger_test() {
  in_temp_dir("rollback", fn(dir) {
    two_migrations(dir)
    let db = database()
    let assert Ok(_) =
      migrate.run(execute(db), query(db), dir, options(False, True))

    should.equal(
      migrate.rollback(execute(db), query(db), dir),
      Ok(Some("002_add_published.sql")),
    )
    should.equal(
      last_statement(db),
      "DELETE FROM schema_migrations WHERE name = '002_add_published.sql'",
    )
    should.be_true(
      list.any(statements(db), fn(statement) {
        statement == "ALTER TABLE posts DROP COLUMN published;"
      }),
    )

    let assert Ok(status) = migrate.status(execute(db), query(db), dir)
    should.equal(status.pending, ["002_add_published.sql"])
  })
}

pub fn rollback_without_a_down_only_drops_the_record_test() {
  in_temp_dir("rollback_no_down", fn(dir) {
    write(dir, "001_seed.sql", "INSERT INTO posts (title) VALUES ('a');")
    let db = database()
    let assert Ok(_) =
      migrate.run(execute(db), query(db), dir, options(False, True))

    should.equal(
      migrate.rollback(execute(db), query(db), dir),
      Ok(Some("001_seed.sql")),
    )
    should.equal(
      last_statement(db),
      "DELETE FROM schema_migrations WHERE name = '001_seed.sql'",
    )

    let assert Ok(status) = migrate.status(execute(db), query(db), dir)
    should.equal(status.pending, ["001_seed.sql"])
  })
}

pub fn rollback_with_nothing_applied_is_a_no_op_test() {
  in_temp_dir("rollback_empty", fn(dir) {
    write(dir, "001_seed.sql", "SELECT 1;")
    let db = database()

    should.equal(migrate.rollback(execute(db), query(db), dir), Ok(None))
  })
}
