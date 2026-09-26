import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleeunit/should
import mastro/jobs.{type Job, Job}
import mastro/session

// -- An in-memory queue -------------------------------------------------------

type Memory {
  Memory(rows: dict.Dict(Int, Job), next_id: Int)
}

type MemoryMessage {
  Insert(Job, process.Subject(Result(Int, String)))
  List(jobs.Filter, process.Subject(Result(List(Job), String)))
  Find(Int, process.Subject(Result(option.Option(Job), String)))
  Update(Job, process.Subject(Result(Nil, String)))
  Delete(Int, process.Subject(Result(Nil, String)))
}

fn queue() -> process.Subject(MemoryMessage) {
  let assert Ok(started) =
    actor.new(Memory(rows: dict.new(), next_id: 1))
    |> actor.on_message(handle_memory)
    |> actor.start

  started.data
}

fn handle_memory(
  state: Memory,
  message: MemoryMessage,
) -> actor.Next(Memory, MemoryMessage) {
  case message {
    Insert(job, reply) -> {
      let job = Job(..job, id: state.next_id)
      process.send(reply, Ok(job.id))
      actor.continue(Memory(
        rows: dict.insert(state.rows, job.id, job),
        next_id: state.next_id + 1,
      ))
    }

    List(filter, reply) -> {
      let rows =
        state.rows
        |> dict.values
        |> list.filter(fn(job) { matches(filter, job) })
        |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
        |> list.take(filter.limit)

      process.send(reply, Ok(rows))
      actor.continue(state)
    }

    Find(id, reply) -> {
      process.send(reply, Ok(option.from_result(dict.get(state.rows, id))))
      actor.continue(state)
    }

    Update(job, reply) -> {
      process.send(reply, Ok(Nil))
      actor.continue(
        Memory(..state, rows: dict.insert(state.rows, job.id, job)),
      )
    }

    Delete(id, reply) -> {
      process.send(reply, Ok(Nil))
      actor.continue(Memory(..state, rows: dict.delete(state.rows, id)))
    }
  }
}

fn matches(filter: jobs.Filter, job: Job) -> Bool {
  let status_ok = case filter.status {
    option.Some(status) -> job.status == status
    option.None -> True
  }

  let kind_ok = case filter.kind {
    option.Some(kind) -> job.kind == kind
    option.None -> True
  }

  status_ok && kind_ok
}

fn store(queue: process.Subject(MemoryMessage)) -> jobs.Store {
  jobs.Store(
    insert: fn(job) {
      process.call_forever(queue, fn(reply) { Insert(job, reply) })
    },
    list: fn(filter) {
      process.call_forever(queue, fn(reply) { List(filter, reply) })
    },
    find: fn(id) { process.call_forever(queue, fn(reply) { Find(id, reply) }) },
    update: fn(job) {
      process.call_forever(queue, fn(reply) { Update(job, reply) })
    },
    delete: fn(id) {
      process.call_forever(queue, fn(reply) { Delete(id, reply) })
    },
  )
}

fn enqueue(queue: process.Subject(MemoryMessage), kind: String) -> Job {
  let assert Ok(job) =
    store(queue)
    |> jobs.enqueue(jobs.Enqueue(
      kind: kind,
      payload: "payload",
      now: 1000,
      run_at: 1000,
      max_attempts: 3,
    ))

  job
}

fn reload(queue: process.Subject(MemoryMessage), id: Int) -> Job {
  let assert Ok(option.Some(job)) = jobs.get(store(queue), id)
  job
}

// -- A handler that fails a given number of times -----------------------------

type Flaky {
  Flaky(failures_left: Int, runs: Int)
}

type FlakyMessage {
  Attempt(process.Subject(Result(Nil, String)))
  Runs(process.Subject(Int))
}

fn flaky(failures: Int) -> process.Subject(FlakyMessage) {
  let assert Ok(started) =
    actor.new(Flaky(failures_left: failures, runs: 0))
    |> actor.on_message(handle_flaky)
    |> actor.start

  started.data
}

fn handle_flaky(
  state: Flaky,
  message: FlakyMessage,
) -> actor.Next(Flaky, FlakyMessage) {
  case message {
    Attempt(reply) -> {
      case state.failures_left > 0 {
        True -> process.send(reply, Error("boom"))
        False -> process.send(reply, Ok(Nil))
      }

      actor.continue(Flaky(
        failures_left: case state.failures_left > 0 {
          True -> state.failures_left - 1
          False -> 0
        },
        runs: state.runs + 1,
      ))
    }

    Runs(reply) -> {
      process.send(reply, state.runs)
      actor.continue(state)
    }
  }
}

fn flaky_handler(flaky: process.Subject(FlakyMessage)) -> jobs.Handler {
  fn(_payload) { process.call_forever(flaky, fn(reply) { Attempt(reply) }) }
}

fn runs(flaky: process.Subject(FlakyMessage)) -> Int {
  process.call_forever(flaky, fn(reply) { Runs(reply) })
}

fn registry(kind: String, handler: jobs.Handler) -> jobs.Registry {
  jobs.registry() |> jobs.register(kind, handler)
}

fn worker(
  queue: process.Subject(MemoryMessage),
  registry: jobs.Registry,
) -> jobs.Worker {
  jobs.worker(store(queue), registry, "worker-1")
}

// -- Enqueue and claim --------------------------------------------------------

pub fn enqueue_starts_pending_test() {
  let queue = queue()
  let job = enqueue(queue, "email")

  should.equal(job.status, jobs.Pending)
  should.equal(job.attempts, 0)
  should.equal(list.length(list_jobs(queue, jobs.all())), 1)
}

pub fn a_delayed_job_is_not_claimed_until_its_time_test() {
  let queue = queue()
  let assert Ok(_) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "later",
        now: 1000,
        run_at: 5000,
        max_attempts: 3,
      ),
    )

  should.equal(jobs.claim(store(queue), "worker-1", 1000), Ok(option.None))

  let assert Ok(option.Some(claimed)) =
    jobs.claim(store(queue), "worker-1", 5000)
  should.equal(claimed.status, jobs.Running)
}

pub fn claiming_marks_the_job_running_test() {
  let queue = queue()
  let job = enqueue(queue, "email")

  let assert Ok(option.Some(claimed)) =
    jobs.claim(store(queue), "worker-1", 1000)
  should.equal(claimed.status, jobs.Running)
  should.equal(claimed.worker, option.Some("worker-1"))
  should.equal(claimed.attempts, 1)
  should.equal(reload(queue, job.id).status, jobs.Running)
}

// -- Fail, retry, discard -----------------------------------------------------

pub fn a_failed_job_comes_back_until_retry_succeeds_test() {
  let queue = queue()
  let flaky = flaky(1)
  let worker = worker(queue, registry("email", flaky_handler(flaky)))
  let assert Ok(job) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "payload",
        now: 1000,
        run_at: 1000,
        max_attempts: 3,
      ),
    )

  // First run fails and schedules a retry.
  let assert Ok(option.Some(failed)) = jobs.run_once(worker, 1000)
  should.equal(failed.status, jobs.Pending)
  should.equal(failed.last_error, option.Some("boom"))
  should.equal(failed.run_at, 1060)

  // A worker ignores it until the backoff has passed.
  should.equal(jobs.claim(store(queue), "worker-1", 1000), Ok(option.None))

  // The retry runs it again, and this time it works.
  let assert Ok(option.Some(second)) = jobs.run_once(worker, 1060)
  should.equal(second.status, jobs.Finished)
  should.equal(second.attempts, 2)
  should.equal(runs(flaky), 2)
  should.equal(reload(queue, job.id).status, jobs.Finished)
}

pub fn a_job_gives_up_after_max_attempts_test() {
  let queue = queue()
  let flaky = flaky(10)
  let worker = worker(queue, registry("email", flaky_handler(flaky)))
  let assert Ok(_) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "payload",
        now: 1000,
        run_at: 1000,
        max_attempts: 2,
      ),
    )

  let assert Ok(_) = jobs.work(worker, 1000, 1)
  let assert Ok(_) = jobs.work(worker, 2000, 1)

  let assert Ok(job) = list_jobs(queue, jobs.failed()) |> list.first

  should.equal(job.status, jobs.Failed)
  should.equal(job.attempts, 2)
  should.be_some(job.finished_at)
  should.equal(jobs.work(worker, 3000, 1), Ok([]))
}

pub fn retry_puts_a_failed_job_back_test() {
  let queue = queue()
  let flaky = flaky(10)
  let worker = worker(queue, registry("email", flaky_handler(flaky)))
  let assert Ok(_) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "payload",
        now: 1000,
        run_at: 1000,
        max_attempts: 1,
      ),
    )
  let assert Ok(_) = jobs.work(worker, 1000, 1)

  let assert Ok(failed) = list_jobs(queue, jobs.failed()) |> list.first

  let assert Ok(retried) = jobs.retry(store(queue), failed, 2000)
  should.equal(retried.status, jobs.Pending)
  should.equal(retried.attempts, 0)
  should.equal(retried.last_error, option.None)
}

pub fn discard_removes_the_job_test() {
  let queue = queue()
  let job = enqueue(queue, "email")

  should.equal(jobs.discard(store(queue), job.id), Ok(Nil))
  should.equal(jobs.get(store(queue), job.id), Ok(option.None))
  should.equal(list.length(list_jobs(queue, jobs.all())), 0)
}

pub fn an_unknown_kind_fails_with_a_message_test() {
  let queue = queue()
  let worker = worker(queue, jobs.registry())
  let assert Ok(_) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "ghost",
        payload: "",
        now: 1000,
        run_at: 1000,
        max_attempts: 1,
      ),
    )

  let assert Ok(option.Some(job)) = jobs.run_once(worker, 1000)
  should.equal(job.status, jobs.Failed)
  should.equal(job.last_error, option.Some("no handler registered for ghost"))
}

// -- Orphans and workers ------------------------------------------------------

pub fn requeue_orphaned_leaves_a_live_worker_alone_test() {
  let queue = queue()
  let assert Ok(stuck) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "",
        now: 1000,
        run_at: 1000,
        max_attempts: 3,
      ),
    )
  let assert Ok(busy) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "",
        now: 1000,
        run_at: 1000,
        max_attempts: 3,
      ),
    )

  let assert Ok(option.Some(_)) = jobs.claim(store(queue), "gone-worker", 1000)
  let assert Ok(option.Some(live)) =
    jobs.claim(store(queue), "live-worker", 1000)
  let assert Ok(live) = jobs.heartbeat(store(queue), live, 9000)

  // Anything that beat after 8000 is alive; the others are stuck.
  should.equal(jobs.requeue_orphaned(store(queue), 8000, 9500), Ok(1))

  should.equal(reload(queue, stuck.id).status, jobs.Pending)
  should.equal(reload(queue, busy.id).status, jobs.Running)
  should.equal(reload(queue, live.id).worker, option.Some("live-worker"))
  should.equal(jobs.live_workers(store(queue), 8000), Ok(["live-worker"]))
}

pub fn prune_finished_forgets_old_rows_test() {
  let queue = queue()
  let flaky = flaky(0)
  let worker = worker(queue, registry("email", flaky_handler(flaky)))
  let assert Ok(old) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "",
        now: 1000,
        run_at: 1000,
        max_attempts: 3,
      ),
    )
  let assert Ok(fresh) =
    jobs.enqueue(
      store(queue),
      jobs.Enqueue(
        kind: "email",
        payload: "",
        now: 1000,
        run_at: 1000,
        max_attempts: 3,
      ),
    )

  let assert Ok(_) = jobs.run_once(worker, 1000)
  let assert Ok(_) = jobs.run_once(worker, 5000)

  should.equal(jobs.prune_finished(store(queue), 3000), Ok(1))
  should.equal(jobs.get(store(queue), old.id), Ok(option.None))
  jobs.get(store(queue), fresh.id) |> should.be_ok
}

// -- Built-in handler ---------------------------------------------------------

pub fn the_prune_sessions_handler_reaches_the_session_store_test() {
  let assert Ok(calls) =
    actor.new(0)
    |> actor.on_message(fn(state, message) {
      case message {
        Count(reply) -> {
          process.send(reply, state)
          actor.continue(state)
        }
        Add(reply) -> {
          process.send(reply, Ok(state + 1))
          actor.continue(state + 1)
        }
      }
    })
    |> actor.start

  let sessions =
    session.Store(
      insert: fn(_) { Error("not used") },
      find: fn(_) { Error("not used") },
      delete: fn(_) { Error("not used") },
      delete_expired: fn(_) {
        process.call_forever(calls.data, fn(reply) { Add(reply) })
      },
      delete_for_user: fn(_) { Error("not used") },
    )

  let handler = jobs.prune_sessions(sessions)
  should.equal(handler(""), Ok(Nil))
  should.equal(process.call_forever(calls.data, fn(reply) { Count(reply) }), 1)
}

type CallMessage {
  Count(process.Subject(Int))
  Add(process.Subject(Result(Int, String)))
}

pub fn enqueue_cron_schedules_the_next_occurrence_test() {
  let queue = queue()
  let assert Ok(job) =
    jobs.enqueue_cron(
      store(queue),
      jobs.Enqueue(
        kind: "prune-sessions",
        payload: "",
        now: 0,
        run_at: 0,
        max_attempts: 3,
      ),
      "0 3 * * *",
    )

  should.equal(job.run_at, 10_800)
}

fn list_jobs(
  queue: process.Subject(MemoryMessage),
  filter: jobs.Filter,
) -> List(Job) {
  let assert Ok(rows) = jobs.list_jobs(store(queue), filter)
  rows
}
