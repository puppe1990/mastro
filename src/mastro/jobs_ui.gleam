//// Local jobs dashboard.
////
//// Mount it in the app at `/jobs`: it is plain HTML, so it works in every
//// environment, including the one you are debugging. Actions are links —
//// `GET /jobs/:id/retry`, `GET /jobs/requeue`, `GET /jobs/clear` — that the
//// app wires to the store; nothing here touches the database.
////
//// ```gleam
//// case wisp.path_segments(req) {
////   ["jobs"] -> jobs_ui.dashboard(view, "") |> wisp.html_response(200)
////   ["jobs", "clear"] -> { clear(store) ; wisp.redirect("/jobs") }
//// }
//// ```

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element, text}
import lustre/element/html
import mastro/jobs.{type Job}

pub type View {
  View(
    jobs: List(Job),
    counts: jobs.Counts,
    kinds: List(String),
    live_workers: List(String),
    orphans: List(Job),
  )
}

/// Everything the page needs, computed from one listing.
pub fn view(all: List(Job), orphans: List(Job), workers: List(String)) -> View {
  View(
    jobs: all,
    counts: jobs.counts(all),
    kinds: all
      |> list.map(fn(job) { job.kind })
      |> list.unique
      |> list.sort(string.compare),
    live_workers: workers,
    orphans: orphans,
  )
}

pub fn dashboard(view: View, _kind: String) -> String {
  html.html([], [
    html.head([], [html.title([], "Jobs")]),
    html.body([], [
      html.h1([], [text("Jobs")]),
      workers_warning(view.live_workers),
      counts_panel(view.counts),
      kind_filter(view.kinds),
      failed_section(view.jobs),
      orphan_section(view.orphans),
      finished_section(view.jobs),
      table(view.jobs),
    ]),
  ])
  |> element.to_document_string
}

pub fn detail(job: Job) -> String {
  html.html([], [
    html.head([], [html.title([], "Job " <> int.to_string(job.id))]),
    html.body([], [
      html.h1([], [text("Job " <> int.to_string(job.id))]),
      html.dl([], [
        row("kind", job.kind),
        row("status", status_name(job.status)),
        row("attempts", attempts(job)),
        row("worker", option_text(job.worker)),
        row("payload", job.payload),
        row("last error", option_text(job.last_error)),
      ]),
      html.div([attribute.class("actions")], [action_links(job)]),
      html.p([], [html.a([attribute.href("/jobs")], [text("Back to jobs")])]),
    ]),
  ])
  |> element.to_document_string
}

// -- Sections -----------------------------------------------------------------

fn workers_warning(workers: List(String)) -> Element(Nil) {
  case list.length(workers) > 1 {
    False -> text("")
    True ->
      html.p([attribute.class("warning")], [
        text(
          int.to_string(list.length(workers))
          <> " workers are alive: they share one queue, so either may claim a job.",
        ),
      ])
  }
}

fn counts_panel(counts: jobs.Counts) -> Element(Nil) {
  html.section([attribute.class("counts")], [
    count("pending", counts.pending),
    count("running", counts.running),
    count("failed", counts.failed),
    count("finished", counts.finished),
  ])
}

fn count(label: String, value: Int) -> Element(Nil) {
  html.div([attribute.class("count")], [
    html.span([attribute.class("count-label")], [text(label)]),
    html.strong(
      [attribute.class("count-value"), attribute.id("count-" <> label)],
      [text(int.to_string(value))],
    ),
  ])
}

fn kind_filter(kinds: List(String)) -> Element(Nil) {
  html.nav([attribute.class("filters")], [
    html.a([attribute.href("/jobs")], [text("all")]),
    ..list.map(kinds, fn(kind) {
      html.a([attribute.href("/jobs?kind=" <> kind)], [text(kind)])
    })
  ])
}

fn failed_section(all: List(Job)) -> Element(Nil) {
  let failed = list.filter(all, fn(job) { job.status == jobs.Failed })

  html.section([attribute.class("failed")], [
    html.h2([], [text("Failed")]),
    ..case failed {
      [] -> [html.p([], [text("Nothing failed.")])]
      _ ->
        list.map(failed, fn(job) {
          html.div([attribute.class("job failed")], [
            html.span([], [text(title(job))]),
            action_links(job),
          ])
        })
    }
  ])
}

fn orphan_section(orphans: List(Job)) -> Element(Nil) {
  case orphans {
    [] -> text("")
    _ ->
      html.section([attribute.class("orphans")], [
        html.h2([], [text("Stuck")]),
        html.p([], [
          text(
            int.to_string(list.length(orphans))
            <> " running jobs stopped beating; their worker is gone.",
          ),
        ]),
        html.p([], [
          html.a([attribute.href("/jobs/requeue"), attribute.class("action")], [
            text("Requeue stuck"),
          ]),
        ]),
        ..list.map(orphans, fn(job) {
          html.div([attribute.class("job orphan")], [
            html.span([], [
              text(title(job) <> " on " <> option_text(job.worker)),
            ]),
            action_links(job),
          ])
        })
      ])
  }
}

fn finished_section(all: List(Job)) -> Element(Nil) {
  let finished = list.filter(all, fn(job) { job.status == jobs.Finished })

  case finished {
    [] -> text("")
    _ ->
      html.section([attribute.class("finished")], [
        html.h2([], [text("Finished")]),
        html.p([], [
          html.a([attribute.href("/jobs/clear"), attribute.class("action")], [
            text("Clear finished"),
          ]),
        ]),
        html.p([], [
          text(
            int.to_string(list.length(finished))
            <> " finished jobs on this page.",
          ),
        ]),
      ])
  }
}

fn table(all: List(Job)) -> Element(Nil) {
  html.table([attribute.class("jobs")], [
    html.thead([], [
      html.tr([], [
        html.th([], [text("id")]),
        html.th([], [text("kind")]),
        html.th([], [text("status")]),
        html.th([], [text("attempts")]),
        html.th([], [text("worker")]),
        html.th([], [text("actions")]),
      ]),
    ]),
    html.tbody([], list.map(all, table_row)),
  ])
}

fn table_row(job: Job) -> Element(Nil) {
  html.tr([attribute.id("job-" <> int.to_string(job.id))], [
    html.td([], [
      html.a([attribute.href("/jobs/" <> int.to_string(job.id))], [
        text(int.to_string(job.id)),
      ]),
    ]),
    html.td([], [text(job.kind)]),
    html.td([attribute.class("status-" <> status_name(job.status))], [
      text(status_name(job.status)),
    ]),
    html.td([], [text(int.to_string(job.attempts))]),
    html.td([], [text(option_text(job.worker))]),
    html.td([], [action_links(job)]),
  ])
}

fn action_links(job: Job) -> Element(Nil) {
  html.span([attribute.class("actions")], [
    html.a(
      [
        attribute.href("/jobs/" <> int.to_string(job.id) <> "/retry"),
        attribute.class("action retry"),
      ],
      [text("Retry")],
    ),
    html.a(
      [
        attribute.href("/jobs/" <> int.to_string(job.id) <> "/discard"),
        attribute.class("action discard"),
      ],
      [text("Discard")],
    ),
  ])
}

fn row(label: String, value: String) -> Element(Nil) {
  html.div([], [
    html.dt([], [text(label)]),
    html.dd([], [text(value)]),
  ])
}

// -- Helpers ------------------------------------------------------------------

fn title(job: Job) -> String {
  job.kind <> " #" <> int.to_string(job.id)
}

fn attempts(job: Job) -> String {
  int.to_string(job.attempts) <> " of " <> int.to_string(job.max_attempts)
}

fn status_name(status: jobs.Status) -> String {
  case status {
    jobs.Pending -> "pending"
    jobs.Running -> "running"
    jobs.Failed -> "failed"
    jobs.Finished -> "finished"
  }
}

fn option_text(value: Option(String)) -> String {
  case value {
    Some(text) -> text
    None -> "—"
  }
}
