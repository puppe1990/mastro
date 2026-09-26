/// `mastro jobs` — the queue commands for the current project.
///
/// Creates `src/<app>/jobs.gleam`, a worker that shares the app's database,
/// then runs it with the given arguments.
///
import gleam/io
import gleam/string
import mastro/cli/format
import mastro/cli/project
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

@external(erlang, "mastro_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn run(args: List(String)) {
  let app = project.app_name()

  case project.detect_db() {
    NoDb -> {
      io.println("No database configured.")
      io.println("Create a project with --db postgres or --db sqlite.")
    }
    db -> {
      let _ = ensure_module(app, db)

      let command = case args {
        [] -> "gleam run -m " <> app <> "/jobs"
        _ -> "gleam run -m " <> app <> "/jobs -- " <> string.join(args, " ")
      }

      io.println(run_cmd(command))
    }
  }
}

/// Write the worker module when the project has none yet.
pub fn ensure_module(app: String, db: DbChoice) -> Bool {
  let path = "src/" <> app <> "/jobs.gleam"

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

fn header(app: String, driver: String) -> String {
  "// Job queue commands.
//
// Usage:
//   gleam run -m " <> app <> "/jobs -- work [--queues a,b] [--concurrency 4]
//   gleam run -m " <> app <> "/jobs -- status
//   gleam run -m " <> app <> "/jobs -- retry <id>
//   gleam run -m " <> app <> "/jobs -- discard <id>
//   gleam run -m " <> app <> "/jobs -- prune
//
// Register your handlers in `registry/0`; the shipped prune-sessions handler
// is `jobs.prune_sessions(sessions_store)`, ready to register under
// `jobs.prune_sessions_kind`.
//
import argv
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option
import gleam/result
import gleam/string
import " <> app <> "/config
import " <> app <> "/data/repo
import mastro/jobs
import mastro/session
import " <> driver <> "

"
}

/// The commands, shared by both drivers once the store exists.
fn commands() -> String {
  "/// The handlers this worker knows. Add yours here.
fn registry() -> jobs.Registry {
  jobs.registry()
  // |> jobs.register(\"send-email\", fn(payload) { mailer.deliver(payload) })
}

fn work(store: jobs.Store, flags: List(String)) -> Nil {
  let id = \"worker-\" <> int.to_string(jobs.now() % 100000)
  let worker =
    jobs.worker(store, registry(), id)
    |> jobs.with_queues(queues(flags))

  io.println(
    \"\"
    <> id
    <> \" draining queues \"
    <> case queues(flags) {
      [] -> \"all\"
      names -> string.join(names, \", \")
    }
    <> \". Ctrl+C to stop.\",
  )

  work_while(worker, concurrency(flags))
}

fn work_while(worker: jobs.Worker, concurrency: Int) -> Nil {
  let now = jobs.now()
  let _ = jobs.work(worker, now, concurrency)
  let _ = jobs.requeue_orphaned(worker.store, now - worker.stale_seconds, now)
  process.sleep(1000)
  work_while(worker, concurrency)
}

fn status(store: jobs.Store) -> Nil {
  case jobs.list_jobs(store, jobs.all() |> jobs.limited(1000)) {
    Error(error) -> io.println(\"Error: \" <> error)
    Ok(jobs_found) -> {
      let counts = jobs.counts(jobs_found)
      io.println(\"pending  \" <> int.to_string(counts.pending))
      io.println(\"running  \" <> int.to_string(counts.running))
      io.println(\"failed   \" <> int.to_string(counts.failed))
      io.println(\"finished \" <> int.to_string(counts.finished))
      io.println(\"\")
      io.println(\"id\\tkind\\tstatus\\tattempts\\tworker\")
      list.each(jobs_found, fn(job) {
        io.println(
          int.to_string(job.id)
          <> \"\\t\"
          <> job.kind
          <> \"\\t\"
          <> status_name(job.status)
          <> \"\\t\"
          <> int.to_string(job.attempts)
          <> \"/\"
          <> int.to_string(job.max_attempts)
          <> \"\\t\"
          <> option.unwrap(job.worker, \"-\"),
        )
      })
    }
  }
}

fn retry(store: jobs.Store, id: String) -> Nil {
  case int.parse(id) {
    Error(_) -> io.println(\"Not an id: \" <> id)
    Ok(id) ->
      case jobs.get(store, id) {
        Ok(option.Some(job)) ->
          case jobs.retry(store, job, jobs.now()) {
            Ok(_) -> io.println(\"Job \" <> id_to_string(id) <> \" is pending again.\")
            Error(error) -> io.println(\"Error: \" <> error)
          }
        Ok(option.None) -> io.println(\"No job \" <> id_to_string(id))
        Error(error) -> io.println(\"Error: \" <> error)
      }
  }
}

fn discard(store: jobs.Store, id: String) -> Nil {
  case int.parse(id) {
    Error(_) -> io.println(\"Not an id: \" <> id)
    Ok(id) ->
      case jobs.discard(store, id) {
        Ok(_) -> io.println(\"Job \" <> id_to_string(id) <> \" discarded.\")
        Error(error) -> io.println(\"Error: \" <> error)
      }
  }
}

fn prune(store: jobs.Store) -> Nil {
  case jobs.prune_finished(store, jobs.now()) {
    Ok(count) -> io.println(int.to_string(count) <> \" finished job(s) forgotten.\")
    Error(error) -> io.println(\"Error: \" <> error)
  }
}

fn print_help() {
  io.println(
    string.join(
      [
        \"mastro jobs — queue commands\",
        \"\",
        \"  work [--queues a,b] [--concurrency N]\",
        \"  status\",
        \"  retry <id>\",
        \"  discard <id>\",
        \"  prune\",
      ],
      \"\\\\n\",
    ),
  )
}

fn queues(flags: List(String)) -> List(String) {
  case flag_value(flags, \"--queues\") {
    option.Some(value) ->
      value
      |> string.split(\",\")
      |> list.map(string.trim)
      |> list.filter(fn(name) { name != \"\" })
    option.None -> []
  }
}

fn concurrency(flags: List(String)) -> Int {
  case flag_value(flags, \"--concurrency\") {
    option.Some(value) ->
      case int.parse(value) {
        Ok(number) if number > 0 -> number
        _ -> 1
      }
    option.None -> 1
  }
}

fn flag_value(flags: List(String), name: String) -> option.Option(String) {
  case flags {
    [flag, value, ..] if flag == name -> option.Some(value)
    [_, ..rest] -> flag_value(rest, name)
    [] -> option.None
  }
}

fn status_name(status: jobs.Status) -> String {
  case status {
    jobs.Pending -> \"pending\"
    jobs.Running -> \"running\"
    jobs.Failed -> \"failed\"
    jobs.Finished -> \"finished\"
  }
}

fn id_to_string(id: Int) -> String {
  int.to_string(id)
}

fn dispatch(store: jobs.Store) -> Nil {
  case argv.load().arguments {
    [\"work\", ..flags] -> work(store, flags)
    [\"status\", ..] -> status(store)
    [\"retry\", id, ..] -> retry(store, id)
    [\"discard\", id, ..] -> discard(store, id)
    [\"prune\", ..] -> prune(store)
    _ -> print_help()
  }
}

"
}

/// SQL the two drivers share; only execution and decoding differ.
fn sql() -> String {
  "fn columns() -> String {
  \"id, kind, payload, status, attempts, max_attempts, run_at, worker, heartbeat_at, finished_at, last_error, inserted_at\"
}

fn list_sql(filter: jobs.Filter) -> String {
  \"SELECT \"
  <> columns()
  <> \" FROM jobs\"
  <> where_sql(filter)
  <> \" ORDER BY id LIMIT \"
  <> int.to_string(filter.limit)
}

fn where_sql(filter: jobs.Filter) -> String {
  let conditions =
    [
      case filter.status {
        option.Some(status) -> option.Some(\"status = '\" <> status_sql(status) <> \"'\")
        option.None -> option.None
      },
      case filter.kind {
        option.Some(kind) -> option.Some(\"kind = '\" <> escape(kind) <> \"'\")
        option.None -> option.None
      },
    ]
    |> option.values

  case conditions {
    [] -> \"\"
    _ -> \" WHERE \" <> string.join(conditions, \" AND \")
  }
}

fn find_sql(id: Int) -> String {
  \"SELECT \" <> columns() <> \" FROM jobs WHERE id = \" <> int.to_string(id)
}

fn insert_sql(job: jobs.Job) -> String {
  \"INSERT INTO jobs (kind, payload, status, attempts, max_attempts, run_at, worker, heartbeat_at, finished_at, last_error, inserted_at) VALUES (\"
  <> value(job.kind)
  <> \", \"
  <> value(job.payload)
  <> \", '\"
  <> status_sql(job.status)
  <> \"', \"
  <> int.to_string(job.attempts)
  <> \", \"
  <> int.to_string(job.max_attempts)
  <> \", \"
  <> int.to_string(job.run_at)
  <> \", \"
  <> optional_text(job.worker)
  <> \", \"
  <> optional_int(job.heartbeat_at)
  <> \", \"
  <> optional_int(job.finished_at)
  <> \", \"
  <> optional_text(job.last_error)
  <> \", \"
  <> int.to_string(job.inserted_at)
  <> \")\"
}

fn update_sql(job: jobs.Job) -> String {
  \"UPDATE jobs SET kind = \"
  <> value(job.kind)
  <> \", payload = \"
  <> value(job.payload)
  <> \", status = '\"
  <> status_sql(job.status)
  <> \"', attempts = \"
  <> int.to_string(job.attempts)
  <> \", max_attempts = \"
  <> int.to_string(job.max_attempts)
  <> \", run_at = \"
  <> int.to_string(job.run_at)
  <> \", worker = \"
  <> optional_text(job.worker)
  <> \", heartbeat_at = \"
  <> optional_int(job.heartbeat_at)
  <> \", finished_at = \"
  <> optional_int(job.finished_at)
  <> \", last_error = \"
  <> optional_text(job.last_error)
  <> \" WHERE id = \"
  <> int.to_string(job.id)
}

fn delete_sql(id: Int) -> String {
  \"DELETE FROM jobs WHERE id = \" <> int.to_string(id)
}

fn status_sql(status: jobs.Status) -> String {
  case status {
    jobs.Pending -> \"pending\"
    jobs.Running -> \"running\"
    jobs.Failed -> \"failed\"
    jobs.Finished -> \"finished\"
  }
}

fn status_from_name(name: String) -> jobs.Status {
  case name {
    \"running\" -> jobs.Running
    \"failed\" -> jobs.Failed
    \"finished\" -> jobs.Finished
    _ -> jobs.Pending
  }
}

fn value(text: String) -> String {
  \"'\" <> escape(text) <> \"'\"
}

fn optional_text(field: option.Option(String)) -> String {
  case field {
    option.Some(text) -> value(text)
    option.None -> \"NULL\"
  }
}

fn optional_int(field: option.Option(Int)) -> String {
  case field {
    option.Some(number) -> int.to_string(number)
    option.None -> \"NULL\"
  }
}

fn escape(text: String) -> String {
  string.replace(text, \"'\", \"''\")
}
"
}

fn module_postgres(app: String) -> String {
  header(app, "pog") <> "pub fn main() {
  let cfg = config.load()
  let assert Ok(db) = repo.connect(cfg)
  dispatch(jobs_store(db))
}

fn jobs_store(db: pog.Connection) -> jobs.Store {
  jobs.Store(
    insert: fn(job) {
      use returned <- result.try(
        pog.query(insert_sql(job) <> \" RETURNING id\")
        |> pog.returning(id_decoder())
        |> pog.execute(db)
        |> result.replace_error(\"insert failed\"),
      )

      case returned.rows {
        [id] -> Ok(id)
        _ -> Error(\"insert failed\")
      }
    },
    list: fn(filter) {
      pog.query(list_sql(filter))
      |> pog.returning(job_decoder())
      |> pog.execute(db)
      |> result.map(fn(returned) { returned.rows })
      |> result.replace_error(\"query failed\")
    },
    find: fn(id) {
      use returned <- result.try(
        pog.query(find_sql(id))
        |> pog.returning(job_decoder())
        |> pog.execute(db)
        |> result.replace_error(\"query failed\"),
      )

      Ok(option.from_result(list.first(returned.rows)))
    },
    update: fn(job) {
      pog.query(update_sql(job))
      |> pog.execute(db)
      |> result.replace(Nil)
      |> result.replace_error(\"update failed\")
    },
    delete: fn(id) {
      pog.query(delete_sql(id))
      |> pog.execute(db)
      |> result.replace(Nil)
      |> result.replace_error(\"delete failed\")
    },
  )
}

fn id_decoder() -> decode.Decoder(Int) {
  use id <- decode.field(0, decode.int)
  decode.success(id)
}

fn job_decoder() -> decode.Decoder(jobs.Job) {
  use id <- decode.field(0, decode.int)
  use kind <- decode.field(1, decode.string)
  use payload <- decode.field(2, decode.string)
  use status <- decode.field(3, decode.string)
  use attempts <- decode.field(4, decode.int)
  use max_attempts <- decode.field(5, decode.int)
  use run_at <- decode.field(6, decode.int)
  use worker <- decode.field(7, decode.optional(decode.string))
  use heartbeat_at <- decode.field(8, decode.optional(decode.int))
  use finished_at <- decode.field(9, decode.optional(decode.int))
  use last_error <- decode.field(10, decode.optional(decode.string))
  use inserted_at <- decode.field(11, decode.int)

  decode.success(jobs.Job(
    id: id,
    kind: kind,
    payload: payload,
    status: status_from_name(status),
    attempts: attempts,
    max_attempts: max_attempts,
    run_at: run_at,
    worker: worker,
    heartbeat_at: heartbeat_at,
    finished_at: finished_at,
    last_error: last_error,
    inserted_at: inserted_at,
  ))
}

" <> sql() <> commands()
}

fn module_sqlite(app: String) -> String {
  header(app, "sqlight") <> "pub fn main() {
  let cfg = config.load()

  use db <- sqlight.with_connection(repo.database_path(cfg))

  dispatch(jobs_store(db))
}

fn jobs_store(db: sqlight.Connection) -> jobs.Store {
  jobs.Store(
    insert: fn(job) {
      use ids <- result.try(
        sqlight.query(
          insert_sql(job) <> \" RETURNING id\",
          on: db,
          with: [],
          expecting: id_decoder(),
        )
        |> result.replace_error(\"insert failed\"),
      )

      case ids {
        [id] -> Ok(id)
        _ -> Error(\"insert failed\")
      }
    },
    list: fn(filter) {
      sqlight.query(
        list_sql(filter),
        on: db,
        with: [],
        expecting: job_decoder(),
      )
      |> result.replace_error(\"query failed\")
    },
    find: fn(id) {
      use found <- result.try(
        sqlight.query(
          find_sql(id),
          on: db,
          with: [],
          expecting: job_decoder(),
        )
        |> result.replace_error(\"query failed\"),
      )

      Ok(option.from_result(list.first(found)))
    },
    update: fn(job) {
      sqlight.exec(update_sql(job), db)
      |> result.replace(Nil)
      |> result.replace_error(\"update failed\")
    },
    delete: fn(id) {
      sqlight.exec(delete_sql(id), db)
      |> result.replace(Nil)
      |> result.replace_error(\"delete failed\")
    },
  )
}

fn id_decoder() -> decode.Decoder(Int) {
  use id <- decode.field(0, decode.int)
  decode.success(id)
}

fn job_decoder() -> decode.Decoder(jobs.Job) {
  use id <- decode.field(0, decode.int)
  use kind <- decode.field(1, decode.string)
  use payload <- decode.field(2, decode.string)
  use status <- decode.field(3, decode.string)
  use attempts <- decode.field(4, decode.int)
  use max_attempts <- decode.field(5, decode.int)
  use run_at <- decode.field(6, decode.int)
  use worker <- decode.field(7, decode.optional(decode.string))
  use heartbeat_at <- decode.field(8, decode.optional(decode.int))
  use finished_at <- decode.field(9, decode.optional(decode.int))
  use last_error <- decode.field(10, decode.optional(decode.string))
  use inserted_at <- decode.field(11, decode.int)

  decode.success(jobs.Job(
    id: id,
    kind: kind,
    payload: payload,
    status: status_from_name(status),
    attempts: attempts,
    max_attempts: max_attempts,
    run_at: run_at,
    worker: worker,
    heartbeat_at: heartbeat_at,
    finished_at: finished_at,
    last_error: last_error,
    inserted_at: inserted_at,
  ))
}

" <> sql() <> commands()
}
