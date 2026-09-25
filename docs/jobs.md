# Jobs

Work that should not happen inside a request — e-mail, reports, webhooks —
goes on a queue that lives in your database. A job survives a restart, a
failure is recorded with the error that caused it, and a stuck job can be
requeued instead of guessed at.

| Where | What |
|-------|------|
| Table | `jobs (id, kind, payload, status, attempts, max_attempts, run_at, worker, heartbeat_at, finished_at, last_error, inserted_at)` |
| Status | `Pending`, `Running`, `Failed`, `Finished` |
| Worker | `mastro jobs work` — claims, runs, heartbeats, finishes or fails |

```sql
CREATE TABLE IF NOT EXISTS jobs (
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
);
```

`jobs.table_sql` and `jobs.index_sql` are ready to paste into a migration.

## Enqueue

```gleam
import mastro/jobs

let assert Ok(job) =
  jobs.enqueue(store, jobs.Enqueue(
    kind: "send-email",
    payload: email,
    now: jobs.now(),
    run_at: jobs.now(),        // in the future to delay it
    max_attempts: 3,
  ))
```

`jobs.enqueue_cron(store, options, "0 3 * * *")` queues the next occurrence
of a cron expression, so a nightly job reschedules itself: call it again
when the job finishes.

## The store

`jobs.Store` is five callbacks — `insert`, `list`, `find`, `update`,
`delete` — so the module has no driver dependency. `mastro jobs` writes the
whole worker for you, store included:

```bash
mastro jobs work --queues send-email,prune-sessions --concurrency 4
mastro jobs status
mastro jobs retry 42
mastro jobs discard 42
mastro jobs prune
```

`work` drains the queue, requeues what a dead worker left behind and sleeps
between passes. `--queues` limits the kinds a worker answers to, so a slow
mail queue cannot hold up the rest.

## Registering handlers

```gleam
import mastro/jobs

let registry =
  jobs.registry()
  |> jobs.register("send-email", fn(payload) { mailer.deliver(payload) })
  |> jobs.register(jobs.prune_sessions_kind, jobs.prune_sessions(sessions_store))
```

A handler gets the payload and returns `Ok(Nil)` or `Error(message)`; the
message is what ends up in `last_error`. The shipped `prune_sessions`
handler clears expired sessions, which is the built-in recurring task.

## What failure means

Failing increments the attempt count and puts the job back with `run_at`
pushed out by the backoff, until `max_attempts` — then the job is `Failed`
and waits for someone to look at it. `jobs.retry` puts it back by hand;
`jobs.discard` throws it away.

A worker claims a job by writing `status = Running`, its own id and a
heartbeat. `jobs.orphaned(store, cutoff)` is what "stuck" means: running
with a heartbeat older than the cutoff. `jobs.requeue_orphaned` puts those
back — and leaves the jobs of a live worker alone, because a busy worker is
not a dead one. `jobs.live_workers` lists the ones still beating.

## Dashboard

Mount it at `/jobs` in the app; `mastro/jobs_ui` renders it and never
touches the database itself:

```gleam
case wisp.path_segments(req), req.method {
  ["jobs"], http.Get -> {
    let filter = jobs.all()
    use found <- result.try(jobs.list_jobs(store, filter))
    use orphans <- result.try(jobs.orphaned(store, jobs.now() - 300))
    use workers <- result.try(jobs.live_workers(store, jobs.now() - 300))

    jobs_ui.view(found, orphans, workers)
    |> jobs_ui.dashboard("")
    |> wisp.html_response(200)
  }

  ["jobs", id, "retry"], http.Get -> // jobs.retry(store, job, jobs.now())
  ["jobs", "requeue"], http.Get -> // jobs.requeue_orphaned(store, cutoff, now)
  ["jobs", "clear"], http.Get -> // jobs.prune_finished(store, now)
}
```

The page shows the counts, filters by kind, and offers Retry/Discard on the
failed rows, Requeue on the stuck ones and Clear on the finished ones. More
than one live worker raises a warning: they share one queue, so either may
claim a job.
