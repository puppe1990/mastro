import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import mastro/doctor

fn healthy() -> dict.Dict(String, String) {
  dict.from_list([
    #("gleam.toml", "name = \"app\"\n\n[dependencies]\nmastro = \">= 0.1.0\""),
    #("priv/static/css/app.css", "body { }"),
    #("priv/static/js/amarra.js", "// amarra"),
    #(
      "priv/static/js/sw.js",
      "const CACHE_VERSION = 1;\n// amarra.js is served network-first",
    ),
    #("priv/static/manifest.webmanifest", "{}"),
    #("priv/static/og.png", "png"),
    #("priv/static/icons/icon-512.png", "png"),
    #(
      "src/app/web/layouts/root_layout.gleam",
      "main([id(\"amarra-main\")], [flash.render()])",
    ),
    #("src/app/router.gleam", "import mastro/jobs_ui"),
    #("src/app/web/health_handler.gleam", "lan_urls"),
    #("src/app/web/chat_views.gleam", "chat-history"),
  ])
}

fn mutate(
  files: dict.Dict(String, String),
  path: String,
  content: String,
) -> dict.Dict(String, String) {
  dict.insert(files, path, content)
}

fn remove(
  files: dict.Dict(String, String),
  path: String,
) -> dict.Dict(String, String) {
  dict.delete(files, path)
}

fn check(report: doctor.Report, name: String) -> doctor.Check {
  let assert Ok(found) =
    report.checks |> list.find(fn(check) { check.name == name })
  found
}

// -- Core ---------------------------------------------------------------------

pub fn core_checks_pass_on_a_healthy_project_test() {
  let report = doctor.run(healthy(), False)

  check(report, "dependency").level |> should.equal(doctor.Pass)
  check(report, "static").level |> should.equal(doctor.Pass)
  check(report, "layout").level |> should.equal(doctor.Pass)
  check(report, "amarra.js").level |> should.equal(doctor.Pass)
  check(report, "manifest").level |> should.equal(doctor.Pass)
  check(report, "service worker").level |> should.equal(doctor.Pass)
  check(report, "jobs").level |> should.equal(doctor.Pass)
}

pub fn missing_amarra_js_fails_test() {
  let report = doctor.run(remove(healthy(), "priv/static/js/amarra.js"), False)

  check(report, "amarra.js").level |> should.equal(doctor.Fail)
  doctor.has_failures(report) |> should.be_true
}

pub fn layout_without_amarra_main_fails_test() {
  let files =
    healthy()
    |> mutate("src/app/web/layouts/root_layout.gleam", "main([], [])")

  check(doctor.run(files, False), "layout").level |> should.equal(doctor.Fail)
}

pub fn missing_dependency_fails_test() {
  let files = healthy() |> mutate("gleam.toml", "name = \"app\"")

  check(doctor.run(files, False), "dependency").level
  |> should.equal(doctor.Fail)
}

pub fn missing_manifest_warns_test() {
  let report =
    doctor.run(remove(healthy(), "priv/static/manifest.webmanifest"), False)

  check(report, "manifest").level |> should.equal(doctor.Warn)
}

pub fn service_worker_without_amarra_fails_test() {
  let files = healthy() |> mutate("priv/static/js/sw.js", "// nothing")

  check(doctor.run(files, False), "service worker").level
  |> should.equal(doctor.Fail)
}

pub fn failures_and_warnings_are_partitioned_test() {
  let report = doctor.run(remove(healthy(), "priv/static/js/amarra.js"), False)

  doctor.failures(report)
  |> list.any(fn(c) { c.name == "amarra.js" })
  |> should.be_true
  doctor.warnings(report) |> list.is_empty |> should.be_false
}

// -- Mobile -------------------------------------------------------------------

pub fn mobile_checks_are_skipped_by_default_test() {
  let report = doctor.run(healthy(), False)

  report.checks |> list.any(fn(c) { c.name == "csp" }) |> should.be_false
}

pub fn mobile_health_without_lan_urls_fails_test() {
  let files =
    healthy()
    |> mutate("src/app/web/health_handler.gleam", "pub fn health() { ok }")

  check(doctor.run(files, True), "health").level |> should.equal(doctor.Fail)
}

pub fn mobile_csp_rejects_google_fonts_test() {
  let files =
    healthy()
    |> mutate("priv/static/css/app.css", "@import url(fonts.googleapis.com)")

  check(doctor.run(files, True), "csp").level |> should.equal(doctor.Fail)
}

pub fn mobile_warns_when_sw_is_not_network_first_test() {
  let files = healthy() |> mutate("priv/static/js/sw.js", "// amarra.js only")

  check(doctor.run(files, True), "sw cache").level |> should.equal(doctor.Warn)
}

pub fn mobile_flash_outside_main_fails_test() {
  let files =
    healthy()
    |> mutate("src/app/web/layouts/root_layout.gleam", "flash.render()")

  check(doctor.run(files, True), "flash").level |> should.equal(doctor.Fail)
}

pub fn mobile_chat_check_points_at_the_chat_helper_test() {
  let files = healthy() |> remove("src/app/web/chat_views.gleam")
  let found = check(doctor.run(files, True), "chat")

  found.level |> should.equal(doctor.Warn)
  found.message |> string.contains("mastro/chat.history()") |> should.be_true
}
