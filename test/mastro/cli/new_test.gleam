/// Integration tests for `mastro new` and the app it scaffolds.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, path_exists,
  set_cwd,
}
import mastro/cli/new
import mastro/cli/pwa

pub fn new_creates_project_structure_test() {
  in_temp_dir("new_basic", fn(dir) {
    let project_dir = dir <> "/my_app"
    new.run(project_dir, [])

    // Core files exist
    file_exists(project_dir <> "/gleam.toml") |> should.be_true
    file_exists(project_dir <> "/README.md") |> should.be_true
    file_exists(project_dir <> "/.gitignore") |> should.be_true
    file_exists(project_dir <> "/src/my_app.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/config.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/context.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/router.gleam") |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/home_handler.gleam")
    |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/error_handler.gleam")
    |> should.be_true
    file_exists(project_dir <> "/src/my_app/web/layouts/root_layout.gleam")
    |> should.be_true
    file_exists(project_dir <> "/test/my_app_test.gleam") |> should.be_true
    file_exists(project_dir <> "/priv/static/css/app.css") |> should.be_true
  })
}

pub fn new_pins_a_stdlib_that_glisten_can_build_against_test() {
  in_temp_dir("new_stdlib_cap", fn(dir) {
    let project_dir = dir <> "/cap_app"
    new.run(project_dir, [])

    // A fresh app must build out of the box: glisten 8.0.3 (through mist)
    // still calls list.range, which gleam_stdlib 0.71.0 removed.
    file_contains(
      project_dir <> "/gleam.toml",
      "gleam_stdlib = \">= 0.44.0 and < 0.71.0\"",
    )
    |> should.be_true
  })
}

pub fn new_postgres_repo_connects_with_a_user_test() {
  in_temp_dir("new_pg_url", fn(dir) {
    let project_dir = dir <> "/pg_url_app"
    new.run(project_dir, ["--db", "postgres"])

    // pog's url_config requires a username in the URL, and a differently
    // configured PostgreSQL should not need a code change.
    file_contains(
      project_dir <> "/src/pg_url_app/data/repo.gleam",
      "postgres://postgres@localhost:5432/pg_url_app_dev",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/pg_url_app/data/repo.gleam",
      "DATABASE_URL",
    )
    |> should.be_true
  })
}

pub fn new_with_postgres_creates_repo_test() {
  in_temp_dir("new_pg", fn(dir) {
    let project_dir = dir <> "/pg_app"
    new.run(project_dir, ["--db", "postgres"])

    file_exists(project_dir <> "/src/pg_app/data/repo.gleam") |> should.be_true
    file_contains(project_dir <> "/gleam.toml", "pog") |> should.be_true
    file_contains(project_dir <> "/src/pg_app/context.gleam", "pog.Connection")
    |> should.be_true
  })
}

pub fn new_with_sqlite_creates_repo_test() {
  in_temp_dir("new_sqlite", fn(dir) {
    let project_dir = dir <> "/sq_app"
    new.run(project_dir, ["--db", "sqlite"])

    file_exists(project_dir <> "/src/sq_app/data/repo.gleam") |> should.be_true
    file_contains(project_dir <> "/gleam.toml", "sqlight") |> should.be_true
    file_contains(project_dir <> "/src/sq_app/context.gleam", "db_path: String")
    |> should.be_true
  })
}

pub fn new_extracts_name_from_path_test() {
  in_temp_dir("new_path", fn(dir) {
    let project_dir = dir <> "/nested/deep/cool_app"
    new.run(project_dir, [])

    // Package name should be "cool_app", not the full path
    file_contains(project_dir <> "/gleam.toml", "name = \"cool_app\"")
    |> should.be_true
    file_exists(project_dir <> "/src/cool_app.gleam") |> should.be_true
  })
}

pub fn new_app_wires_dev_logs_and_the_banner_test() {
  in_temp_dir("new_logs", fn(dir) {
    let project_dir = dir <> "/logs_app"
    new.run(project_dir, ["--db", "sqlite"])

    file_contains(project_dir <> "/src/logs_app.gleam", "dev_log.install(logs)")
    |> should.be_true
    file_contains(
      project_dir <> "/src/logs_app.gleam",
      "net.pick_port(cfg.port",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/logs_app.gleam",
      "net.banner(\"logs_app\"",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/logs_app/context.gleam",
      "logs: dev_log.Store",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/logs_app/config.gleam",
      "log_format: LogFormat",
    )
    |> should.be_true

    file_contains(project_dir <> "/src/logs_app/router.gleam", "dev_log.viewer")
    |> should.be_true
    file_contains(
      project_dir <> "/src/logs_app/router.gleam",
      "dev_log.request_log",
    )
    |> should.be_true
  })
}

// =============================================================================
// health and PWA
// =============================================================================

pub fn new_app_serves_health_with_lan_urls_test() {
  in_temp_dir("health", fn(dir) {
    let project_dir = dir <> "/health_app"
    new.run(project_dir, [])

    file_exists(project_dir <> "/src/health_app/web/health_handler.gleam")
    |> should.be_true
    file_contains(
      project_dir <> "/src/health_app/web/health_handler.gleam",
      "health.respond",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/health_app/router.gleam",
      "health_handler.index",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/health_app/web/layouts/root_layout.gleam",
      "amarra-main",
    )
    |> should.be_true
  })
}

pub fn new_app_has_i18n_and_meta_test() {
  in_temp_dir("meta", fn(dir) {
    let project_dir = dir <> "/meta_app"
    new.run(project_dir, [])

    file_contains(
      project_dir <> "/src/meta_app/config.gleam",
      "locale: i18n.Locale",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/meta_app/config.gleam",
      "pub const app_name",
    )
    |> should.be_true
    file_contains(project_dir <> "/src/meta_app/config.gleam", "meta.site_from")
    |> should.be_true
    file_contains(
      project_dir <> "/src/meta_app/web/layouts/root_layout.gleam",
      "meta.head_elements",
    )
    |> should.be_true
    file_contains(
      project_dir <> "/src/meta_app/web/home_handler.gleam",
      "config.site",
    )
    |> should.be_true
  })
}

pub fn pwa_installs_assets_and_bump_increments_test() {
  in_temp_dir("pwa", fn(dir) {
    let project_dir = dir <> "/pwa_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    pwa.run([])

    file_exists("priv/static/js/amarra.js") |> should.be_true
    file_exists("priv/static/manifest.webmanifest") |> should.be_true
    path_exists("priv/static/icons/icon-512.png") |> should.be_true
    path_exists("priv/static/icons/icon-512-maskable.png") |> should.be_true
    path_exists("priv/static/og.png") |> should.be_true
    file_contains("priv/static/js/sw.js", "CACHE_VERSION = 1") |> should.be_true

    pwa.run(["--bump"])
    file_contains("priv/static/js/sw.js", "CACHE_VERSION = 2") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}
