//// Development observability: an in-process log of requests and SQL, the
//// middleware that records requests, and the `/logs` viewer.
////
//// The store is a small actor holding the last `max` entries, newest first.
//// `install` puts it in a process-global slot so generated repository code
//// can call `sql` without threading a store through every function;
//// `request_log` takes the store explicitly, which keeps its tests simple.
////
//// This is a development tool. `viewer` answers 404 unless the app is in dev
//// and the request arrived over localhost, and the middleware records
//// nothing when the store is disabled.

import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/string
import mastro/net
import wisp.{type Response}

// -- Configuration ------------------------------------------------------------

/// How a log line is shaped and whether it is emitted at all.
pub type Options {
  Options(json: Bool, enabled: Bool)
}

pub fn options(json: Bool, enabled: Bool) -> Options {
  Options(json: json, enabled: enabled)
}

/// Records and prints nothing: the production setting.
pub fn disabled() -> Options {
  Options(json: False, enabled: False)
}

// -- Entries ------------------------------------------------------------------

/// One recorded event.
pub type Entry {
  Request(method: String, path: String, status: Int, duration_ms: Int)
  Sql(statement: String, params: Int, duration_ms: Int)
}

/// The store: an actor plus the options it prints with. Opaque so callers
/// go through `record`/`recent` rather than poking at the subject.
pub opaque type Store {
  Store(subject: process.Subject(Message), options: Options)
}

pub opaque type Message {
  Record(entry: Entry)
  Recent(reply: process.Subject(List(Entry)))
  Clear
}

type State {
  State(entries: List(Entry), max: Int, options: Options)
}

// -- Store --------------------------------------------------------------------

/// Start a store that keeps at most `max` entries.
pub fn start(max: Int, options: Options) -> Store {
  let assert Ok(started) =
    actor.new(State(entries: [], max: max, options: options))
    |> actor.on_message(handle)
    |> actor.start

  Store(subject: started.data, options: options)
}

/// Append an entry, dropping the oldest once `max` is reached.
pub fn record(store: Store, entry: Entry) -> Nil {
  actor.send(store.subject, Record(entry: entry))
}

/// The entries held right now, newest first.
pub fn recent(store: Store) -> List(Entry) {
  let reply = process.new_subject()
  actor.send(store.subject, Recent(reply: reply))
  case process.receive(reply, 5000) {
    Ok(entries) -> entries
    Error(_) -> []
  }
}

pub fn clear(store: Store) -> Nil {
  actor.send(store.subject, Clear)
}

// -- Global slot --------------------------------------------------------------

@external(erlang, "mastro_dev_log_ffi", "install")
fn ffi_install(store: Store) -> Nil

@external(erlang, "mastro_dev_log_ffi", "installed")
fn ffi_installed() -> Result(Store, Nil)

@external(erlang, "mastro_dev_log_ffi", "uninstall")
fn ffi_uninstall() -> Nil

/// Publish the store so `sql` can find it without an argument.
pub fn install(store: Store) -> Nil {
  ffi_install(store)
}

pub fn uninstall() -> Nil {
  ffi_uninstall()
}

pub fn installed() -> Result(Store, Nil) {
  ffi_installed()
}

// -- Recording ----------------------------------------------------------------

/// The clock the store times with, shared with `net`.
pub fn now_ms() -> Int {
  net.now_ms()
}

/// Record a SQL statement against the installed store. A no-op when the app
/// never installed one — the CLI, tests and production all hit that path.
pub fn sql(statement: String, params: Int, duration_ms: Int) -> Nil {
  case installed() {
    Ok(store) ->
      record(
        store,
        Sql(statement: statement, params: params, duration_ms: duration_ms),
      )
    Error(_) -> Nil
  }
}

/// Middleware: time the handler and record the request. When the store is
/// disabled it is a pass-through, so wrapping production costs nothing.
pub fn request_log(
  store: Store,
  req: request.Request(a),
  next: fn() -> Response,
) -> Response {
  case store.options.enabled {
    False -> next()
    True -> {
      let start = net.now_ms()
      let resp = next()
      record(
        store,
        Request(
          method: http.method_to_string(req.method),
          path: req.path,
          status: resp.status,
          duration_ms: net.now_ms() - start,
        ),
      )
      resp
    }
  }
}

// -- Formatting ---------------------------------------------------------------

/// Format one entry for a line of output.
pub fn format(entry: Entry, options: Options) -> String {
  case options.json {
    True -> encode(entry)
    False -> plain(entry)
  }
}

/// A JSON object with a `kind` discriminator, one line per entry.
pub fn encode(entry: Entry) -> String {
  case entry {
    Request(method:, path:, status:, duration_ms:) ->
      json.object([
        #("kind", json.string("request")),
        #("method", json.string(method)),
        #("path", json.string(path)),
        #("status", json.int(status)),
        #("duration_ms", json.int(duration_ms)),
      ])
      |> json.to_string

    Sql(statement:, params:, duration_ms:) ->
      json.object([
        #("kind", json.string("sql")),
        #("statement", json.string(statement)),
        #("params", json.int(params)),
        #("duration_ms", json.int(duration_ms)),
      ])
      |> json.to_string
  }
}

/// The plain-text fallback when `LOG_FORMAT=text`.
pub fn plain(entry: Entry) -> String {
  case entry {
    Request(method:, path:, status:, duration_ms:) ->
      int.to_string(status)
      <> " "
      <> string.uppercase(method)
      <> " "
      <> path
      <> " ("
      <> int.to_string(duration_ms)
      <> "ms)"

    Sql(statement:, params:, duration_ms:) ->
      "[sql "
      <> int.to_string(duration_ms)
      <> "ms, "
      <> int.to_string(params)
      <> " params] "
      <> statement
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Record(entry:) -> {
      print(state.options, entry)
      let entries = [entry, ..state.entries] |> list.take(state.max)
      actor.continue(State(..state, entries: entries))
    }

    Recent(reply:) -> {
      process.send(reply, state.entries)
      actor.continue(state)
    }

    Clear -> actor.continue(State(..state, entries: []))
  }
}

fn print(options: Options, entry: Entry) {
  case options.enabled {
    True -> io.println(format(entry, options))
    False -> Nil
  }
}

// -- Viewer -------------------------------------------------------------------

/// `GET /logs`: the recent entries as an auto-refreshing page. Only answers
/// while the app is in development and the request came from localhost.
pub fn viewer(store: Store, dev: Bool, req: request.Request(a)) -> Response {
  case dev, localhost(req) {
    True, True -> wisp.html_response(render_page(recent(store)), 200)
    _, _ -> wisp.not_found()
  }
}

/// Whether the request's `Host` names the loopback interface. A request with
/// no `Host` header (HTTP/1.0, in-process tests) counts as local.
pub fn localhost(req: request.Request(a)) -> Bool {
  case request.get_header(req, "host") {
    Ok(host) -> is_local_host(host)
    Error(_) -> True
  }
}

fn is_local_host(host: String) -> Bool {
  case string.split(host, "]") {
    [bracketed, ..] ->
      case bracketed <> "]" == "[::1]" {
        True -> True
        False -> plain_host_is_local(host)
      }
    [] -> plain_host_is_local(host)
  }
}

fn plain_host_is_local(host: String) -> Bool {
  let name = case string.split(host, ":") {
    [name, ..] -> name
    [] -> host
  }
  name == "localhost" || name == "127.0.0.1"
}

fn render_page(entries: List(Entry)) -> String {
  let rows =
    entries
    |> list.map(render_row)
    |> string.join("\n")

  let body = case entries {
    [] -> "<p class=\"empty\">No requests or SQL yet.</p>"
    _ -> "<table><tbody>" <> rows <> "</tbody></table>"
  }

  "<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <meta http-equiv=\"refresh\" content=\"2\">
  <title>mastro logs</title>
  <style>" <> page_css() <> "</style>
</head>
<body>
  <header><h1>mastro logs</h1><span class=\"hint\">auto-refreshes every 2s</span></header>
  " <> body <> "
</body>
</html>"
}

fn render_row(entry: Entry) -> String {
  case entry {
    Request(method:, path:, status:, duration_ms:) ->
      "<tr><td><span class=\"kind request\">request</span></td><td>"
      <> escape(int.to_string(status))
      <> " "
      <> escape(string.uppercase(method))
      <> " "
      <> escape(path)
      <> "</td><td class=\"ms\">"
      <> escape(int.to_string(duration_ms))
      <> "ms</td></tr>"

    Sql(statement:, params:, duration_ms:) ->
      "<tr><td><span class=\"kind sql\">sql</span></td><td><code>"
      <> escape(statement)
      <> "</code></td><td class=\"ms\">"
      <> escape(int.to_string(params))
      <> " params · "
      <> escape(int.to_string(duration_ms))
      <> "ms</td></tr>"
  }
}

fn page_css() -> String {
  "
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: system-ui, -apple-system, sans-serif;
      background: #0f172a;
      color: #e2e8f0;
      line-height: 1.5;
    }
    header {
      display: flex;
      align-items: baseline;
      gap: 0.75rem;
      padding: 1rem 1.5rem;
      border-bottom: 1px solid #1e293b;
      position: sticky;
      top: 0;
      background: #0f172a;
    }
    h1 { font-size: 1.1rem; }
    .hint { color: #64748b; font-size: 0.8rem; }
    table { width: 100%; border-collapse: collapse; }
    td {
      padding: 0.5rem 0.75rem;
      border-bottom: 1px solid #1e293b;
      font-size: 0.85rem;
      vertical-align: top;
    }
    .ms { color: #94a3b8; white-space: nowrap; text-align: right; }
    code { font-family: ui-monospace, monospace; color: #cbd5e1; }
    .kind {
      display: inline-block;
      padding: 0.1rem 0.4rem;
      border-radius: 3px;
      font-size: 0.7rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .request { background: #1d4ed8; color: white; }
    .sql { background: #047857; color: white; }
    .empty { padding: 2rem 1.5rem; color: #64748b; }
  "
}

fn escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}
