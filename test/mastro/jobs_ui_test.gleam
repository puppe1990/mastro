import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import mastro/jobs.{Job}
import mastro/jobs_ui

// -- Dashboard ----------------------------------------------------------------

fn sample_view(workers: List(String)) -> jobs_ui.View {
  let failed =
    Job(
      id: 2,
      kind: "email",
      payload: "",
      status: jobs.Failed,
      attempts: 3,
      max_attempts: 3,
      run_at: 1000,
      worker: option.None,
      heartbeat_at: option.None,
      finished_at: option.Some(1100),
      last_error: option.Some("boom"),
      inserted_at: 1000,
    )

  let orphan =
    Job(
      id: 3,
      kind: "report",
      payload: "",
      status: jobs.Running,
      attempts: 1,
      max_attempts: 3,
      run_at: 1000,
      worker: option.Some("gone"),
      heartbeat_at: option.Some(1000),
      finished_at: option.None,
      last_error: option.None,
      inserted_at: 1000,
    )

  let pending =
    Job(
      id: 1,
      kind: "email",
      payload: "",
      status: jobs.Pending,
      attempts: 0,
      max_attempts: 3,
      run_at: 1000,
      worker: option.None,
      heartbeat_at: option.None,
      finished_at: option.None,
      last_error: option.None,
      inserted_at: 1000,
    )

  let finished =
    Job(
      id: 4,
      kind: "email",
      payload: "",
      status: jobs.Finished,
      attempts: 1,
      max_attempts: 3,
      run_at: 1000,
      worker: option.None,
      heartbeat_at: option.None,
      finished_at: option.Some(1100),
      last_error: option.None,
      inserted_at: 1000,
    )

  jobs_ui.view([pending, failed, orphan, finished], [orphan], workers)
}

pub fn the_dashboard_renders_counts_and_actions_test() {
  let html = jobs_ui.dashboard(sample_view(["worker-1"]), "")

  should.be_true(string.contains(html, "count-pending"))
  should.be_true(string.contains(html, "count-failed"))
  should.be_true(string.contains(html, ">1<"))
  should.be_true(string.contains(html, "/jobs/2/retry"))
  should.be_true(string.contains(html, "/jobs/2/discard"))
  should.be_true(string.contains(html, "/jobs/requeue"))
  should.be_true(string.contains(html, "/jobs/clear"))
  should.be_true(string.contains(html, "/jobs/3"))
  should.be_true(string.contains(html, "email"))
  should.be_true(string.contains(html, "report"))
}

pub fn the_dashboard_filters_by_kind_test() {
  let html = jobs_ui.dashboard(sample_view([]), "")

  should.be_true(string.contains(html, "/jobs?kind=email"))
  should.be_true(string.contains(html, "/jobs?kind=report"))
}

pub fn two_live_workers_raise_a_warning_test() {
  let one = jobs_ui.dashboard(sample_view(["worker-1"]), "")
  should.be_false(string.contains(one, "workers are alive"))

  let two = jobs_ui.dashboard(sample_view(["worker-1", "worker-2"]), "")
  should.be_true(string.contains(two, "2 workers are alive"))
}

pub fn the_detail_page_shows_the_payload_and_error_test() {
  let view = sample_view([])
  let assert Ok(failed) =
    view.jobs |> list.find(fn(job) { job.status == jobs.Failed })

  let html = jobs_ui.detail(failed)
  should.be_true(string.contains(html, "Job 2"))
  should.be_true(string.contains(html, "boom"))
  should.be_true(string.contains(html, "3 of 3"))
  should.be_true(string.contains(html, "/jobs/2/retry"))
}
