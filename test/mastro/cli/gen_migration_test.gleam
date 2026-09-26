/// Integration tests for migrations, the db module and the jobs module.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/migration as gen_migration
import mastro/cli/gen/resource as gen_resource
import mastro/cli/jobs_cmd
import mastro/cli/migrate_cmd
import mastro/cli/new
import mastro/cli/types

pub fn gen_migration_writes_up_and_down_sections_test() {
  in_temp_dir("gen_migration", fn(dir) {
    let project_dir = dir <> "/mig_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_migration.migration("add_email")

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

    gen_resource.resource("posts", ["title:string"])

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

    gen_resource.resource("posts", ["title:string"])

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
