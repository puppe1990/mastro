import gleam/http/request
import gleam/result
import gleam/string
import gleeunit/should
import mastro/dev_log
import wisp

fn body_of(resp: wisp.Response) -> String {
  case resp.body {
    wisp.Text(body) -> body
    _ -> ""
  }
}

fn local_request() -> request.Request(String) {
  request.new() |> request.set_header("host", "localhost:4000")
}

// -- Store --------------------------------------------------------------------

pub fn recent_is_newest_first_test() {
  let store = dev_log.start(10, dev_log.disabled())

  dev_log.record(
    store,
    dev_log.Sql(statement: "SELECT 1", params: 0, duration_ms: 1),
  )
  dev_log.record(
    store,
    dev_log.Sql(statement: "SELECT 2", params: 0, duration_ms: 1),
  )

  dev_log.recent(store)
  |> should.equal([
    dev_log.Sql(statement: "SELECT 2", params: 0, duration_ms: 1),
    dev_log.Sql(statement: "SELECT 1", params: 0, duration_ms: 1),
  ])
}

pub fn the_store_keeps_at_most_max_entries_test() {
  let store = dev_log.start(2, dev_log.disabled())

  dev_log.record(
    store,
    dev_log.Sql(statement: "one", params: 0, duration_ms: 1),
  )
  dev_log.record(
    store,
    dev_log.Sql(statement: "two", params: 0, duration_ms: 1),
  )
  dev_log.record(
    store,
    dev_log.Sql(statement: "three", params: 0, duration_ms: 1),
  )

  dev_log.recent(store)
  |> should.equal([
    dev_log.Sql(statement: "three", params: 0, duration_ms: 1),
    dev_log.Sql(statement: "two", params: 0, duration_ms: 1),
  ])
}

pub fn clear_empties_the_store_test() {
  let store = dev_log.start(10, dev_log.disabled())
  dev_log.record(
    store,
    dev_log.Sql(statement: "SELECT 1", params: 0, duration_ms: 1),
  )

  dev_log.clear(store)

  dev_log.recent(store) |> should.equal([])
}

// -- Formatting ---------------------------------------------------------------

pub fn json_request_carries_a_kind_test() {
  let line =
    dev_log.encode(dev_log.Request(
      method: "GET",
      path: "/posts",
      status: 200,
      duration_ms: 12,
    ))

  line |> string.contains("\"kind\":\"request\"") |> should.be_true
  line |> string.contains("\"path\":\"/posts\"") |> should.be_true
  line |> string.contains("\"status\":200") |> should.be_true
}

pub fn json_sql_carries_a_kind_test() {
  let line =
    dev_log.encode(dev_log.Sql(statement: "SELECT 1", params: 2, duration_ms: 5))

  line |> string.contains("\"kind\":\"sql\"") |> should.be_true
  line |> string.contains("\"params\":2") |> should.be_true
}

pub fn plain_request_reads_like_a_log_line_test() {
  dev_log.plain(dev_log.Request(
    method: "get",
    path: "/posts",
    status: 404,
    duration_ms: 3,
  ))
  |> should.equal("404 GET /posts (3ms)")
}

pub fn plain_sql_keeps_the_statement_test() {
  dev_log.plain(dev_log.Sql(statement: "SELECT 1", params: 0, duration_ms: 7))
  |> should.equal("[sql 7ms, 0 params] SELECT 1")
}

// -- Middleware ---------------------------------------------------------------

pub fn request_log_records_the_request_test() {
  let store = dev_log.start(10, dev_log.options(False, True))
  let req = request.new() |> request.set_path("/about")

  let resp = dev_log.request_log(store, req, fn() { wisp.ok() })

  resp.status |> should.equal(200)
  case dev_log.recent(store) {
    [dev_log.Request(path:, status:, ..)] -> {
      path |> should.equal("/about")
      status |> should.equal(200)
    }
    _ -> should.fail()
  }
}

pub fn disabled_request_log_records_nothing_test() {
  let store = dev_log.start(10, dev_log.disabled())

  let _ = dev_log.request_log(store, request.new(), fn() { wisp.ok() })

  dev_log.recent(store) |> should.equal([])
}

// -- Global slot --------------------------------------------------------------

pub fn sql_without_an_installed_store_is_a_noop_test() {
  dev_log.uninstall()

  dev_log.sql("SELECT 1", 0, 1)

  dev_log.installed() |> result.is_error |> should.be_true
}

pub fn installed_sql_is_recorded_test() {
  dev_log.uninstall()
  let store = dev_log.start(10, dev_log.options(True, True))
  dev_log.install(store)

  dev_log.sql("SELECT 42", 1, 9)

  case dev_log.recent(store) {
    [dev_log.Sql(statement:, params:, duration_ms:)] -> {
      statement |> should.equal("SELECT 42")
      params |> should.equal(1)
      duration_ms |> should.equal(9)
    }
    _ -> should.fail()
  }

  dev_log.uninstall()
}

// -- Viewer -------------------------------------------------------------------

pub fn localhost_accepts_loopback_hosts_test() {
  dev_log.localhost(request.new()) |> should.be_true
  dev_log.localhost(
    request.new() |> request.set_header("host", "localhost:4000"),
  )
  |> should.be_true
  dev_log.localhost(
    request.new() |> request.set_header("host", "127.0.0.1:4000"),
  )
  |> should.be_true
  dev_log.localhost(request.new() |> request.set_header("host", "[::1]:4000"))
  |> should.be_true
}

pub fn localhost_rejects_a_public_host_test() {
  dev_log.localhost(request.new() |> request.set_header("host", "example.com"))
  |> should.be_false
  dev_log.localhost(
    request.new() |> request.set_header("host", "10.0.0.5:4000"),
  )
  |> should.be_false
}

pub fn viewer_is_404_outside_development_test() {
  let store = dev_log.start(10, dev_log.disabled())

  dev_log.viewer(store, False, local_request()).status |> should.equal(404)
}

pub fn viewer_is_404_when_not_local_test() {
  let store = dev_log.start(10, dev_log.disabled())
  let req = request.new() |> request.set_header("host", "example.com")

  dev_log.viewer(store, True, req).status |> should.equal(404)
}

pub fn viewer_shows_the_recent_entries_test() {
  let store = dev_log.start(10, dev_log.disabled())
  dev_log.record(
    store,
    dev_log.Request(
      method: "GET",
      path: "/secret-ish",
      status: 200,
      duration_ms: 3,
    ),
  )

  let resp = dev_log.viewer(store, True, local_request())

  resp.status |> should.equal(200)
  body_of(resp) |> string.contains("/secret-ish") |> should.be_true
}

pub fn viewer_escapes_html_in_statements_test() {
  let store = dev_log.start(10, dev_log.disabled())
  dev_log.record(
    store,
    dev_log.Sql(statement: "SELECT '<script>'", params: 0, duration_ms: 1),
  )

  body_of(dev_log.viewer(store, True, local_request()))
  |> string.contains("<script>")
  |> should.be_false
}
