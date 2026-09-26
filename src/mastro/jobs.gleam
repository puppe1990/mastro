//// Persistent job queue.
////
//// Jobs live in the app's database, so a queue survives a restart, a failed
//// job can be retried and a stuck one can be requeued. The port is five
//// callbacks — insert, list, find, update, delete — so the module carries no
//// driver dependency and the logic stays testable with a dictionary.
////
//// A worker claims a job, heartbeats while it runs, and finishes or fails it.
//// Failing increments the attempt count and puts the job back on the queue
//// until `max_attempts`, when it becomes `Failed` and waits for a human or a
//// retry. `now` is always passed in, so none of this needs a clock to test.
////
//// ```gleam
//// let worker = jobs.worker(store, registry, "worker-1")
//// jobs.work(worker, jobs.now(), 10)
//// ```

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import mastro/session

pub const table_sql = "CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  max_attempts INTEGER NOT NULL,
  run_at INTEGER NOT NULL,
  worker TEXT,
  heartbeat_at INTEGER,
  finished_at INTEGER,
  last_error TEXT,
  inserted_at INTEGER NOT NULL
)"

pub const index_sql = "CREATE INDEX IF NOT EXISTS jobs_status_run_at_index ON jobs (status, run_at)"

/// The kind the shipped prune-sessions handler answers to.
pub const prune_sessions_kind = "prune-sessions"

pub type Status {
  Pending
  Running
  Failed
  Finished
}

pub type Job {
  Job(
    id: Int,
    kind: String,
    payload: String,
    status: Status,
    attempts: Int,
    max_attempts: Int,
    run_at: Int,
    worker: Option(String),
    heartbeat_at: Option(Int),
    finished_at: Option(Int),
    last_error: Option(String),
    inserted_at: Int,
  )
}

/// The SQL port.
pub type Store {
  Store(
    /// Insert the job, returning its id.
    insert: fn(Job) -> Result(Int, String),
    list: fn(Filter) -> Result(List(Job), String),
    find: fn(Int) -> Result(Option(Job), String),
    /// Write the whole row back.
    update: fn(Job) -> Result(Nil, String),
    delete: fn(Int) -> Result(Nil, String),
  )
}

pub type Filter {
  Filter(status: Option(Status), kind: Option(String), limit: Int)
}

pub type Enqueue {
  Enqueue(
    kind: String,
    payload: String,
    now: Int,
    run_at: Int,
    max_attempts: Int,
  )
}

pub type Counts {
  Counts(pending: Int, running: Int, failed: Int, finished: Int)
}

pub type Handler =
  fn(String) -> Result(Nil, String)

/// Handlers by kind.
pub type Registry =
  Dict(String, Handler)

pub type Worker {
  Worker(
    store: Store,
    registry: Registry,
    id: String,
    max_attempts: Int,
    backoff_seconds: Int,
    stale_seconds: Int,
    /// Kinds this worker answers to. Empty means every queue.
    queues: List(String),
  )
}

// -- Filters ------------------------------------------------------------------

pub fn all() -> Filter {
  Filter(status: None, kind: None, limit: 100)
}

pub fn of_status(filter: Filter, status: Status) -> Filter {
  Filter(..filter, status: Some(status))
}

pub fn of_kind(filter: Filter, kind: String) -> Filter {
  Filter(..filter, kind: Some(kind))
}

pub fn limited(filter: Filter, limit: Int) -> Filter {
  Filter(..filter, limit: limit)
}

/// The rows the dashboard shows: running, then failed, then pending.
pub fn failed() -> Filter {
  all() |> of_status(Failed)
}

pub fn pending() -> Filter {
  all() |> of_status(Pending)
}

pub fn running() -> Filter {
  all() |> of_status(Running)
}

pub fn finished() -> Filter {
  all() |> of_status(Finished)
}

// -- Enqueue ------------------------------------------------------------------

/// Enqueue a job. `run_at` in the future delays it: the worker only claims
/// jobs whose time has come.
pub fn enqueue(store: Store, options: Enqueue) -> Result(Job, String) {
  let job =
    Job(
      id: 0,
      kind: options.kind,
      payload: options.payload,
      status: Pending,
      attempts: 0,
      max_attempts: options.max_attempts,
      run_at: options.run_at,
      worker: None,
      heartbeat_at: None,
      finished_at: None,
      last_error: None,
      inserted_at: options.now,
    )

  use id <- result.try(store.insert(job))
  Ok(Job(..job, id: id))
}

/// Queue a recurring kind: the next occurrence becomes a delayed job. Call it
/// again when the job finishes to keep the schedule going.
pub fn enqueue_cron(
  store: Store,
  options: Enqueue,
  expression: String,
) -> Result(Job, String) {
  use next <- result.try(cron_next(expression, options.now))
  enqueue(store, Enqueue(..options, run_at: next))
}

// -- Reading ------------------------------------------------------------------

pub fn list_jobs(store: Store, filter: Filter) -> Result(List(Job), String) {
  store.list(filter)
}

pub fn get(store: Store, id: Int) -> Result(Option(Job), String) {
  store.find(id)
}

pub fn counts(jobs: List(Job)) -> Counts {
  list.fold(
    jobs,
    Counts(pending: 0, running: 0, failed: 0, finished: 0),
    fn(counts, job) {
      case job.status {
        Pending -> Counts(..counts, pending: counts.pending + 1)
        Running -> Counts(..counts, running: counts.running + 1)
        Failed -> Counts(..counts, failed: counts.failed + 1)
        Finished -> Counts(..counts, finished: counts.finished + 1)
      }
    },
  )
}

/// Jobs a worker left running: their heartbeat is older than the cutoff,
/// which is what "stuck" means. A live worker's jobs are not in here.
pub fn orphaned(store: Store, stale_before: Int) -> Result(List(Job), String) {
  use jobs <- result.try(store.list(running() |> limited(1000)))
  Ok(list.filter(jobs, fn(job) { stale(job, stale_before) }))
}

/// Workers that beat recently enough to be alive.
pub fn live_workers(
  store: Store,
  stale_before: Int,
) -> Result(List(String), String) {
  use jobs <- result.try(store.list(running() |> limited(1000)))

  Ok(
    jobs
    |> list.filter(fn(job) { !stale(job, stale_before) })
    |> list.filter_map(fn(job) { option.to_result(job.worker, Nil) })
    |> list.unique,
  )
}

fn open_queue(queues: List(String), job: Job) -> Bool {
  case queues {
    [] -> True
    _ -> list.contains(queues, job.kind)
  }
}

fn stale(job: Job, stale_before: Int) -> Bool {
  case job.heartbeat_at {
    Some(beat) -> beat < stale_before
    None -> True
  }
}

// -- Transitions --------------------------------------------------------------

/// Take the oldest pending job whose time has come and mark it running.
pub fn claim(
  store: Store,
  worker: String,
  now: Int,
) -> Result(Option(Job), String) {
  claim_from(store, worker, now, [])
}

/// Claim, but only among the given kinds. An empty list takes any kind.
pub fn claim_from(
  store: Store,
  worker worker: String,
  now now: Int,
  queues queues: List(String),
) -> Result(Option(Job), String) {
  use jobs <- result.try(store.list(pending() |> limited(100)))

  let ready =
    jobs
    |> list.filter(fn(job) { job.run_at <= now && open_queue(queues, job) })
    |> list.sort(fn(a, b) { int.compare(a.run_at, b.run_at) })

  case ready {
    [] -> Ok(None)
    [job, ..] -> {
      let claimed =
        Job(
          ..job,
          status: Running,
          worker: Some(worker),
          heartbeat_at: Some(now),
          attempts: job.attempts + 1,
        )

      use _ <- result.try(store.update(claimed))
      Ok(Some(claimed))
    }
  }
}

/// The job finished its work.
pub fn complete(store: Store, job: Job, now: Int) -> Result(Job, String) {
  let finished =
    Job(..job, status: Finished, finished_at: Some(now), worker: None)

  use _ <- result.try(store.update(finished))
  Ok(finished)
}

/// The job raised. It goes back on the queue with a later `run_at` until it
/// runs out of attempts, when it fails for good.
pub fn fail(
  store: Store,
  job: Job,
  error: String,
  now: Int,
  backoff_seconds: Int,
) -> Result(Job, String) {
  let used_up = job.attempts >= job.max_attempts

  let failed =
    Job(
      ..job,
      status: case used_up {
        True -> Failed
        False -> Pending
      },
      run_at: now + backoff_seconds,
      worker: None,
      heartbeat_at: None,
      last_error: Some(error),
      finished_at: case used_up {
        True -> Some(now)
        False -> None
      },
    )

  use _ <- result.try(store.update(failed))
  Ok(failed)
}

/// Put a failed job back on the queue by hand.
pub fn retry(store: Store, job: Job, now: Int) -> Result(Job, String) {
  let retried =
    Job(
      ..job,
      status: Pending,
      attempts: 0,
      run_at: now,
      worker: None,
      heartbeat_at: None,
      finished_at: None,
      last_error: None,
    )

  use _ <- result.try(store.update(retried))
  Ok(retried)
}

/// Put every stuck job back on the queue. Jobs of live workers are left
/// alone: they are not stuck, they are busy.
pub fn requeue_orphaned(
  store: Store,
  stale_before: Int,
  now: Int,
) -> Result(Int, String) {
  use jobs <- result.try(orphaned(store, stale_before))

  use count <- result.try(
    jobs
    |> list.try_fold(0, fn(count, job) {
      use _ <- result.try(store.update(
        Job(
          ..job,
          status: Pending,
          run_at: now,
          worker: None,
          heartbeat_at: None,
        ),
      ))
      Ok(count + 1)
    }),
  )

  Ok(count)
}

/// Throw the job away, whatever state it is in.
pub fn discard(store: Store, id: Int) -> Result(Nil, String) {
  store.delete(id)
}

/// Forget the finished jobs that ended before `before`.
pub fn prune_finished(store: Store, before: Int) -> Result(Int, String) {
  use jobs <- result.try(store.list(finished() |> limited(1000)))

  use count <- result.try(
    jobs
    |> list.filter(fn(job) {
      case job.finished_at {
        Some(at) -> at < before
        None -> True
      }
    })
    |> list.try_fold(0, fn(count, job) {
      use _ <- result.try(store.delete(job.id))
      Ok(count + 1)
    }),
  )

  Ok(count)
}

/// Record that the worker is still alive, so its jobs are not requeued.
pub fn heartbeat(store: Store, job: Job, now: Int) -> Result(Job, String) {
  let beating = Job(..job, heartbeat_at: Some(now))
  use _ <- result.try(store.update(beating))
  Ok(beating)
}

// -- Worker -------------------------------------------------------------------

pub fn worker(store: Store, registry: Registry, id: String) -> Worker {
  Worker(
    store: store,
    registry: registry,
    id: id,
    max_attempts: 3,
    backoff_seconds: 60,
    stale_seconds: 300,
    queues: [],
  )
}

/// Only answer to these kinds; an empty list takes everything.
pub fn with_queues(worker: Worker, queues: List(String)) -> Worker {
  Worker(..worker, queues: queues)
}

pub fn with_max_attempts(worker: Worker, max_attempts: Int) -> Worker {
  Worker(..worker, max_attempts: max_attempts)
}

pub fn with_backoff(worker: Worker, backoff_seconds: Int) -> Worker {
  Worker(..worker, backoff_seconds: backoff_seconds)
}

pub fn with_stale_after(worker: Worker, stale_seconds: Int) -> Worker {
  Worker(..worker, stale_seconds: stale_seconds)
}

/// Claim one job, run its handler and record the outcome. Returns the job as
/// it was left, or `None` when the queue had nothing ready.
pub fn run_once(worker: Worker, now: Int) -> Result(Option(Job), String) {
  use claimed <- result.try(claim_from(
    worker.store,
    worker.id,
    now,
    worker.queues,
  ))

  case claimed {
    None -> Ok(None)
    Some(job) ->
      case dict.get(worker.registry, job.kind) {
        Error(_) ->
          fail(
            worker.store,
            job,
            "no handler registered for " <> job.kind,
            now,
            worker.backoff_seconds,
          )
          |> result.map(Some)

        Ok(handler) ->
          case handler(job.payload) {
            Ok(_) -> complete(worker.store, job, now) |> result.map(Some)
            Error(error) ->
              fail(worker.store, job, error, now, worker.backoff_seconds)
              |> result.map(Some)
          }
      }
  }
}

/// Run at most `max_jobs` jobs, stopping early when the queue is empty.
pub fn work(
  worker: Worker,
  now: Int,
  max_jobs: Int,
) -> Result(List(Job), String) {
  use jobs <- result.try(work_loop(worker, now, max_jobs, []))
  Ok(list.reverse(jobs))
}

fn work_loop(
  worker: Worker,
  now: Int,
  remaining: Int,
  done: List(Job),
) -> Result(List(Job), String) {
  case remaining <= 0 {
    True -> Ok(done)
    False -> {
      use next <- result.try(run_once(worker, now))
      case next {
        None -> Ok(done)
        Some(job) -> work_loop(worker, now, remaining - 1, [job, ..done])
      }
    }
  }
}

// -- Registry -----------------------------------------------------------------

pub fn registry() -> Registry {
  dict.new()
}

pub fn register(registry: Registry, kind: String, handler: Handler) -> Registry {
  dict.insert(registry, kind, handler)
}

/// The shipped handler: clear the sessions that expired. Register it under
/// `prune_sessions_kind` and schedule it with a cron expression.
pub fn prune_sessions(sessions: session.Store) -> Handler {
  fn(_payload) {
    session.prune(sessions, session.now())
    |> result.replace(Nil)
  }
}

// -- Cron ---------------------------------------------------------------------

/// The next time the five field expression fires, in unix seconds.
///
/// Supports `*`, `5`, `1-5`, `1,3,5` and `*/5` in every field. Day of month
/// and day of week are OR-ed when both are restricted, as Vixie cron does.
pub fn cron_next(expression: String, from: Int) -> Result(Int, String) {
  use fields <- result.try(parse_cron(expression))
  find_next(fields, next_minute(from), 0)
}

type Cron {
  Cron(
    minutes: List(Int),
    hours: List(Int),
    days: List(Int),
    months: List(Int),
    weekdays: List(Int),
    any_day: Bool,
    any_weekday: Bool,
  )
}

fn parse_cron(expression: String) -> Result(Cron, String) {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [minutes, hours, days, months, weekdays] -> {
      use minutes <- result.try(field(minutes, 0, 59))
      use hours <- result.try(field(hours, 0, 23))
      use days <- result.try(field(days, 1, 31))
      use months <- result.try(field(months, 1, 12))
      use weekdays <- result.try(field(weekdays, 0, 6))

      Ok(Cron(
        minutes: minutes,
        hours: hours,
        days: days,
        months: months,
        weekdays: weekdays,
        any_day: string.trim(days_raw(expression)) == "*",
        any_weekday: string.trim(weekday_raw(expression)) == "*",
      ))
    }
    _ -> Error("a cron expression has five fields: " <> expression)
  }
}

fn days_raw(expression: String) -> String {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [_, _, days, ..] -> days
    _ -> ""
  }
}

fn weekday_raw(expression: String) -> String {
  case string.split(string.trim(expression), " ") |> list.filter(is_not_blank) {
    [_, _, _, _, weekdays] -> weekdays
    _ -> ""
  }
}

fn is_not_blank(part: String) -> Bool {
  string.trim(part) != ""
}

/// Every value from `start` to `stop`, both included — what a cron field
/// expands to. Field bounds always run low to high.
fn inclusive_range(start: Int, stop: Int) -> List(Int) {
  int.range(from: start, to: stop + 1, with: [], run: list.prepend)
  |> list.reverse
}

fn field(text: String, low: Int, high: Int) -> Result(List(Int), String) {
  case string.trim(text) {
    "*" -> Ok(inclusive_range(low, high))
    _ -> {
      use parts <- result.try(
        text
        |> string.split(",")
        |> list.try_map(fn(part) { part_values(part, low, high) }),
      )
      Ok(parts |> list.flatten |> list.unique |> list.sort(int.compare))
    }
  }
}

fn part_values(part: String, low: Int, high: Int) -> Result(List(Int), String) {
  let #(range, stride) = case string.split(part, "/") {
    [range, stride_text] ->
      case int.parse(stride_text) {
        Ok(stride) if stride > 0 -> #(range, stride)
        _ -> #(range, 1)
      }
    _ -> #(part, 1)
  }

  use #(start, values) <- result.try(case string.trim(range) {
    "*" -> Ok(#(low, inclusive_range(low, high)))
    _ -> bounds(range, low, high)
  })

  Ok(
    values
    |> list.filter(fn(value) { { value - start } % stride == 0 }),
  )
}

fn bounds(
  range: String,
  low: Int,
  high: Int,
) -> Result(#(Int, List(Int)), String) {
  case string.split(string.trim(range), "-") {
    [start, end] ->
      case int.parse(start), int.parse(end) {
        Ok(start), Ok(end) if start >= low && end <= high && start <= end ->
          Ok(#(start, inclusive_range(start, end)))
        _, _ -> Error("bad range: " <> range)
      }
    [single] ->
      case int.parse(single) {
        Ok(value) if value >= low && value <= high -> Ok(#(value, [value]))
        _ -> Error("bad value: " <> single)
      }
    _ -> Error("bad field: " <> range)
  }
}

/// The next minute boundary strictly after `from`.
fn next_minute(from: Int) -> Int {
  from - from % 60 + 60
}

fn find_next(cron: Cron, candidate: Int, days_tried: Int) -> Result(Int, String) {
  case days_tried > 400 {
    True -> Error("no run time in the next year")
    False ->
      case day_matches(cron, candidate) {
        False -> find_next(cron, start_of_next_day(candidate), days_tried + 1)
        True ->
          case hour_matches(cron, candidate) {
            False -> find_next(cron, start_of_next_hour(candidate), days_tried)
            True ->
              case minute_matches(cron, candidate) {
                True -> Ok(candidate)
                False -> find_next(cron, candidate + 60, days_tried)
              }
          }
      }
  }
}

fn day_matches(cron: Cron, at: Int) -> Bool {
  let #(date, _) = to_calendar(at)

  case list.contains(cron.months, calendar.month_to_int(date.month)) {
    False -> False
    True -> {
      let day = list.contains(cron.days, date.day)
      let weekday = list.contains(cron.weekdays, weekday_of(at))

      // `*` in a field means the field does not constrain the day. When
      // both are restricted they are OR-ed, as Vixie cron does.
      case cron.any_day, cron.any_weekday {
        True, True -> True
        True, False -> weekday
        False, True -> day
        False, False -> day || weekday
      }
    }
  }
}

fn hour_matches(cron: Cron, at: Int) -> Bool {
  let #(_, time) = to_calendar(at)
  list.contains(cron.hours, time.hours)
}

fn minute_matches(cron: Cron, at: Int) -> Bool {
  let #(_, time) = to_calendar(at)
  list.contains(cron.minutes, time.minutes)
}

fn start_of_next_hour(at: Int) -> Int {
  at - at % 3600 + 3600
}

fn start_of_next_day(at: Int) -> Int {
  at - at % 86_400 + 86_400
}

fn to_calendar(at: Int) -> #(calendar.Date, calendar.TimeOfDay) {
  timestamp.to_calendar(timestamp.from_unix_seconds(at), duration.seconds(0))
}

/// 1970-01-01 was a Thursday, which is 4 when Sunday is 0.
fn weekday_of(at: Int) -> Int {
  let days = { at - at % 86_400 } / 86_400
  { days + 4 } % 7
}

/// The current unix time in seconds.
pub fn now() -> Int {
  system_time_seconds()
}

@external(erlang, "mastro_rate_limit_ffi", "system_time_seconds")
fn system_time_seconds() -> Int
