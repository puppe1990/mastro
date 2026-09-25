//// `mastro doctor` checks.
////
//// The checks are pure: they read a snapshot of the project (`path` →
//// `content`, one entry per file) and return a list of results. The CLI
//// builds the snapshot from disk; tests build it in memory, so every rule
//// is exercised without a project.
////
//// Levels:
//// - `Pass` — the guardrail is in place.
//// - `Warn` — the app can run, but something is missing or a placeholder.
//// - `Fail` — the app is missing something the Amarra contract needs.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Level {
  Pass
  Warn
  Fail
}

pub type Check {
  Check(name: String, level: Level, message: String)
}

pub type Report {
  Report(checks: List(Check))
}

/// Run every core check, plus the mobile ones when asked.
pub fn run(files: Dict(String, String), mobile: Bool) -> Report {
  let mobile_checks = case mobile {
    True -> mobile_checks(files)
    False -> []
  }

  Report(list.append(core_checks(files), mobile_checks))
}

pub fn failures(report: Report) -> List(Check) {
  report.checks |> list.filter(fn(check) { check.level == Fail })
}

pub fn warnings(report: Report) -> List(Check) {
  report.checks |> list.filter(fn(check) { check.level == Warn })
}

pub fn has_failures(report: Report) -> Bool {
  report
  |> failures
  |> list.is_empty
  |> fn(empty) { !empty }
}

pub fn symbol(level: Level) -> String {
  case level {
    Pass -> "ok  "
    Warn -> "warn"
    Fail -> "fail"
  }
}

// -- Core ---------------------------------------------------------------------

fn core_checks(files: Dict(String, String)) -> List(Check) {
  [
    dependency_check(files),
    static_dir_check(files),
    layout_check(files),
    amarra_js_check(files),
    manifest_check(files),
    service_worker_check(files),
    jobs_ui_check(files),
    assets_check(files),
  ]
}

fn dependency_check(files: Dict(String, String)) -> Check {
  let fail =
    Check(
      "dependency",
      Fail,
      "gleam.toml does not list mastro — is this a mastro project?",
    )

  case find(files, "gleam.toml") {
    Some(#(_, content)) ->
      case string.contains(content, "mastro") {
        True -> Check("dependency", Pass, "gleam.toml depends on mastro")
        False -> fail
      }
    None -> fail
  }
}

fn static_dir_check(files: Dict(String, String)) -> Check {
  case any_path(files, fn(path) { string.starts_with(path, "priv/static") }) {
    True -> Check("static", Pass, "priv/static/ exists")
    False ->
      Check(
        "static",
        Fail,
        "priv/static/ is missing — run `mastro assets setup`",
      )
  }
}

fn layout_check(files: Dict(String, String)) -> Check {
  case any_content(files, in_layouts, "amarra-main") {
    True -> Check("layout", Pass, "the layout renders #amarra-main")
    False ->
      Check(
        "layout",
        Fail,
        "the layout must render <main id=\"amarra-main\"> — mastro/layout.app does this for you",
      )
  }
}

/// `amarra.js` is what makes Drive and the kit hooks work on the client.
fn amarra_js_check(files: Dict(String, String)) -> Check {
  case has_file(files, "priv/static/js/amarra.js") {
    True -> Check("amarra.js", Pass, "priv/static/js/amarra.js is present")
    False ->
      Check(
        "amarra.js",
        Fail,
        "priv/static/js/amarra.js is missing — run `mastro pwa` to install the default assets",
      )
  }
}

fn manifest_check(files: Dict(String, String)) -> Check {
  case has_file(files, "manifest.webmanifest") {
    True -> Check("manifest", Pass, "manifest.webmanifest is present")
    False ->
      Check(
        "manifest",
        Warn,
        "manifest.webmanifest is missing — run `mastro pwa` to add PWA support",
      )
  }
}

fn service_worker_check(files: Dict(String, String)) -> Check {
  case find(files, "sw.js") {
    None ->
      Check(
        "service worker",
        Warn,
        "sw.js is missing — run `mastro pwa` to cache the app offline",
      )
    Some(#(_, content)) ->
      case string.contains(content, "amarra.js") {
        True -> Check("service worker", Pass, "sw.js caches amarra.js")
        False ->
          Check(
            "service worker",
            Fail,
            "sw.js does not serve priv/static/js/amarra.js",
          )
      }
  }
}

fn jobs_ui_check(files: Dict(String, String)) -> Check {
  case any_content(files, fn(_) { True }, "jobs_ui") {
    True -> Check("jobs", Pass, "the jobs dashboard is mounted")
    False ->
      Check(
        "jobs",
        Warn,
        "jobs dashboard not mounted — see docs/jobs.md if the app uses jobs",
      )
  }
}

fn assets_check(files: Dict(String, String)) -> Check {
  let has_og = has_file(files, "og.png")
  let has_icon = has_file(files, "icon-512.png")

  case has_og, has_icon {
    True, True ->
      Check(
        "assets",
        Warn,
        "og.png and icon-512.png are present — replace the placeholders before launch",
      )
    _, _ ->
      Check(
        "assets",
        Warn,
        "og.png / icons/icon-512.png are missing — run `mastro pwa` and replace the placeholders",
      )
  }
}

// -- Mobile -------------------------------------------------------------------

fn mobile_checks(files: Dict(String, String)) -> List(Check) {
  [
    flash_check(files),
    csp_check(files),
    service_worker_network_first_check(files),
    chat_check(files),
    health_check(files),
  ]
}

/// Flash needs to live inside `#amarra-main`, or Drive morphs it away.
fn flash_check(files: Dict(String, String)) -> Check {
  let in_main = any_content(files, in_layouts, "amarra-main")
  let has_flash = any_content(files, in_layouts, "flash")

  case in_main, has_flash {
    True, True -> Check("flash", Pass, "flash renders inside #amarra-main")
    False, _ ->
      Check("flash", Fail, "render flash inside <main id=\"amarra-main\">")
    True, False ->
      Check(
        "flash",
        Warn,
        "no flash component found in the layout — add web/components/flash.gleam",
      )
  }
}

/// System fonts only: Google Fonts is blocked by the default CSP on mobile.
fn csp_check(files: Dict(String, String)) -> Check {
  case any_content(files, fn(_) { True }, "fonts.googleapis.com") {
    True ->
      Check(
        "csp",
        Fail,
        "fonts.googleapis.com is blocked by the default CSP — use system fonts",
      )
    False -> Check("csp", Pass, "no blocked font origin in the source")
  }
}

fn service_worker_network_first_check(files: Dict(String, String)) -> Check {
  case find(files, "sw.js") {
    None ->
      Check(
        "sw cache",
        Warn,
        "no sw.js — run `mastro pwa` so amarra.js is served network-first",
      )
    Some(#(_, content)) ->
      case
        string.contains(content, "amarra.js"),
        string.contains(content, "network-first")
      {
        True, True ->
          Check("sw cache", Pass, "amarra.js is served network-first")
        True, False ->
          Check(
            "sw cache",
            Warn,
            "serve amarra.js network-first in sw.js so dev edits are not cached",
          )
        False, _ -> Check("sw cache", Fail, "sw.js does not mention amarra.js")
      }
  }
}

fn chat_check(files: Dict(String, String)) -> Check {
  case any_content(files, fn(_) { True }, "chat-history") {
    True ->
      Check("chat", Pass, "the chat Stream container #chat-history exists")
    False ->
      Check(
        "chat",
        Warn,
        "chat Stream container #chat-history not found — render `mastro/chat.history()` if the app has chat",
      )
  }
}

fn health_check(files: Dict(String, String)) -> Check {
  case find_containing_path(files, "health") {
    None ->
      Check(
        "health",
        Warn,
        "no /health route — add one that returns lan_urls for on-device testing",
      )
    Some(#(_, content)) ->
      case
        string.contains(content, "lan_urls")
        || string.contains(content, "health.respond")
      {
        True -> Check("health", Pass, "/health returns lan_urls")
        False ->
          Check(
            "health",
            Fail,
            "/health must include lan_urls so the device can find the dev server",
          )
      }
  }
}

// -- Helpers ------------------------------------------------------------------

fn in_layouts(path: String) -> Bool {
  string.contains(path, "/web/layouts/")
}

fn find(
  files: Dict(String, String),
  suffix: String,
) -> Option(#(String, String)) {
  dict.to_list(files)
  |> list.find(fn(entry) { string.ends_with(entry.0, suffix) })
  |> to_option
}

fn has_file(files: Dict(String, String), suffix: String) -> Bool {
  find(files, suffix) != None
}

fn find_containing_path(
  files: Dict(String, String),
  needle: String,
) -> Option(#(String, String)) {
  dict.to_list(files)
  |> list.find(fn(entry) { string.contains(entry.0, needle) })
  |> to_option
}

fn to_option(value: Result(a, Nil)) -> Option(a) {
  case value {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn any_path(files: Dict(String, String), predicate: fn(String) -> Bool) -> Bool {
  dict.keys(files) |> list.any(predicate)
}

fn any_content(
  files: Dict(String, String),
  path_predicate: fn(String) -> Bool,
  needle: String,
) -> Bool {
  dict.to_list(files)
  |> list.any(fn(entry) {
    path_predicate(entry.0) && string.contains(entry.1, needle)
  })
}
