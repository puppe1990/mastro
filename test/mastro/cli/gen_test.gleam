/// Integration tests for code generators.
///
/// These tests run generators in a temp directory and verify the output
/// files exist and contain expected content.
///
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import mastro/cli/gen
import mastro/cli/jobs_cmd
import mastro/cli/migrate_cmd
import mastro/cli/new
import mastro/cli/types
import mastro/doctor
import simplifile

// =============================================================================
// Helpers
// =============================================================================

fn in_temp_dir(name: String, f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/mastro_test_" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  f(dir)
  let _ = simplifile.delete_all([dir])
  Nil
}

fn file_exists(path: String) -> Bool {
  case simplifile.read(path) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn file_contains(path: String, substring: String) -> Bool {
  case simplifile.read(path) {
    Ok(content) -> string.contains(content, substring)
    Error(_) -> False
  }
}

// =============================================================================
// mastro new
// =============================================================================

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
// doctor
// =============================================================================

pub fn doctor_fails_on_a_fresh_sqlite_app_without_amarra_js_test() {
  in_temp_dir("doctor", fn(dir) {
    let project_dir = dir <> "/doc_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    let files =
      dict.from_list([
        #("gleam.toml", simplifile.read("gleam.toml") |> result.unwrap("")),
        #(
          "src/doc_app/web/layouts/root_layout.gleam",
          simplifile.read("src/doc_app/web/layouts/root_layout.gleam")
            |> result.unwrap(""),
        ),
      ])

    let report = doctor.run(files, False)
    doctor.has_failures(report) |> should.be_true

    let assert Ok(amarra) =
      list.find(report.checks, fn(check) { check.name == "amarra.js" })
    amarra.level |> should.equal(doctor.Fail)

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen resource (runs inside a generated project)
// =============================================================================

pub fn gen_resource_creates_all_files_test() {
  in_temp_dir("gen_resource", fn(dir) {
    let project_dir = dir <> "/res_app"
    new.run(project_dir, ["--db", "postgres"])

    // Change to project dir and run gen resource
    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string", "body:text", "published:bool"])

    // Verify files exist
    file_exists("src/res_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/res_app/web/post_views.gleam") |> should.be_true
    file_exists("src/res_app/web/forms/post_form.gleam") |> should.be_true
    file_exists("src/res_app/domain/post.gleam") |> should.be_true
    file_exists("src/res_app/data/post_repo.gleam") |> should.be_true
    file_exists("src/res_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("test/res_app/web/post_handler_test.gleam") |> should.be_true

    // Verify router was patched
    file_contains("src/res_app/router.gleam", "post_handler") |> should.be_true
    file_contains("src/res_app/router.gleam", "[\"posts\"]") |> should.be_true

    // Verify domain type
    file_contains("src/res_app/domain/post.gleam", "pub type Post")
    |> should.be_true
    file_contains("src/res_app/domain/post.gleam", "title: String")
    |> should.be_true

    // Verify migration SQL
    file_contains(
      "src/res_app/data/migrations/001_create_posts.sql",
      "CREATE TABLE",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn gen_two_resources_no_duplication_test() {
  in_temp_dir("gen_two", fn(dir) {
    let project_dir = dir <> "/two_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string"])
    gen.resource("comments", ["body:text"])

    // Both handlers exist
    file_exists("src/two_app/web/post_handler.gleam") |> should.be_true
    file_exists("src/two_app/web/comment_handler.gleam") |> should.be_true

    // Router has both resources, no duplication
    let assert Ok(router) = simplifile.read("src/two_app/router.gleam")
    let post_count =
      router
      |> string.split("post_handler.index")
      |> list.length
    // Should appear exactly twice: once in import area doesn't count, once in routes
    // Actually split produces N+1 parts for N occurrences
    { post_count <= 3 } |> should.be_true

    // Separate migrations
    file_exists("src/two_app/data/migrations/001_create_posts.sql")
    |> should.be_true
    file_exists("src/two_app/data/migrations/002_create_comments.sql")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen page
// =============================================================================

pub fn gen_page_creates_handler_and_patches_router_test() {
  in_temp_dir("gen_page", fn(dir) {
    let project_dir = dir <> "/page_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.page("about")

    file_exists("src/page_app/web/about_handler.gleam") |> should.be_true
    file_exists("test/page_app/web/about_handler_test.gleam") |> should.be_true
    file_contains("src/page_app/router.gleam", "about_handler")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen auth
// =============================================================================

pub fn gen_auth_creates_all_files_test() {
  in_temp_dir("gen_auth", fn(dir) {
    let project_dir = dir <> "/auth_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.auth()

    file_exists("src/auth_app/domain/user.gleam") |> should.be_true
    file_exists("src/auth_app/domain/auth.gleam") |> should.be_true
    file_exists("src/auth_app/data/user_repo.gleam") |> should.be_true
    file_exists("src/auth_app/web/auth_handler.gleam") |> should.be_true
    file_exists("src/auth_app/web/auth_views.gleam") |> should.be_true
    file_exists("src/auth_app/web/forms/auth_form.gleam") |> should.be_true
    file_exists("src/auth_app/web/middleware/auth.gleam") |> should.be_true

    // Router patched
    file_contains("src/auth_app/router.gleam", "auth_handler") |> should.be_true
    file_contains("src/auth_app/router.gleam", "login") |> should.be_true
    file_contains("src/auth_app/router.gleam", "register") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// gen island
// =============================================================================

pub fn gen_island_creates_files_test() {
  in_temp_dir("gen_island", fn(dir) {
    let project_dir = dir <> "/island_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.island("counter")

    file_exists("src/island_app/web/islands/counter.gleam") |> should.be_true
    file_exists("src/island_app/web/islands/counter_embed.gleam")
    |> should.be_true

    file_contains("src/island_app/web/islands/counter.gleam", "pub fn main()")
    |> should.be_true
    file_contains(
      "src/island_app/web/islands/counter_embed.gleam",
      "pub fn render()",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// migrations and the database module
// =============================================================================

pub fn gen_migration_writes_up_and_down_sections_test() {
  in_temp_dir("gen_migration", fn(dir) {
    let project_dir = dir <> "/mig_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.migration("add_email")

    let path = "src/mig_app/data/migrations/001_add_email.sql"
    file_contains(path, "-- up") |> should.be_true
    file_contains(path, "-- down") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn resource_migration_carries_its_own_rollback_test() {
  in_temp_dir("resource_down", fn(dir) {
    let project_dir = dir <> "/roll_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string"])

    let path = "src/roll_app/data/migrations/001_create_posts.sql"
    file_contains(path, "-- up") |> should.be_true
    file_contains(path, "DROP TABLE posts;") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn sqlite_resource_repo_routes_through_the_logging_helper_test() {
  in_temp_dir("sqlite_repo_log", fn(dir) {
    let project_dir = dir <> "/sql_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen.resource("posts", ["title:string"])

    file_contains("src/sql_app/data/repo.gleam", "pub fn query(")
    |> should.be_true
    file_contains("src/sql_app/data/repo.gleam", "dev_log.sql(")
    |> should.be_true
    file_contains("src/sql_app/data/post_repo.gleam", "repo.query(")
    |> should.be_true
    file_contains("src/sql_app/data/post_repo.gleam", "sqlight.with_connection")
    |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn db_module_answers_every_subcommand_test() {
  in_temp_dir("db_module", fn(dir) {
    let project_dir = dir <> "/db_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    migrate_cmd.ensure_module("db_app", types.Postgres)

    let path = "src/db_app/migrate.gleam"
    file_exists(path) |> should.be_true
    file_contains(path, "\"status\"") |> should.be_true
    file_contains(path, "\"rollback\"") |> should.be_true
    file_contains(path, "\"prune-sessions\"") |> should.be_true
    file_contains(path, "migrate.run(") |> should.be_true
    file_contains(path, "migrate.rollback(") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn jobs_module_answers_every_subcommand_test() {
  in_temp_dir("jobs_module", fn(dir) {
    let project_dir = dir <> "/jobs_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    jobs_cmd.ensure_module("jobs_app", types.Postgres)

    let path = "src/jobs_app/jobs.gleam"
    file_exists(path) |> should.be_true
    file_contains(path, "\"work\"") |> should.be_true
    file_contains(path, "\"status\"") |> should.be_true
    file_contains(path, "\"retry\"") |> should.be_true
    file_contains(path, "\"discard\"") |> should.be_true
    file_contains(path, "\"prune\"") |> should.be_true
    file_contains(path, "--queues") |> should.be_true
    file_contains(path, "jobs.Store(") |> should.be_true
    file_contains(path, "with_queues(") |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

// =============================================================================
// FFI helper
// =============================================================================

@external(erlang, "mastro_test_ffi", "set_cwd")
fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "mastro_test_ffi", "current_directory")
fn current_directory() -> Result(String, Nil)
