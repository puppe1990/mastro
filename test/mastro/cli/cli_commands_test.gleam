/// Integration tests for the other CLI commands: component, destroy, doctor.
///
import gleam/dict
import gleam/list
import gleam/result
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/component
import mastro/cli/destroy
import mastro/cli/gen/resource as gen_resource
import mastro/cli/new
import mastro/doctor
import simplifile

pub fn gen_component_seeds_an_override_test() {
  in_temp_dir("component", fn(dir) {
    let project_dir = dir <> "/comp_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    component.run("locale-toggle", [])

    file_exists("src/comp_app/web/components/locale_toggle.gleam")
    |> should.be_true
    file_contains(
      "src/comp_app/web/components/locale_toggle.gleam",
      "pub fn render(",
    )
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn destroy_resource_removes_files_and_routes_test() {
  in_temp_dir("destroy", fn(dir) {
    let project_dir = dir <> "/dest_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string"])
    file_exists("src/dest_app/web/post_handler.gleam") |> should.be_true

    destroy.run("resource", "posts", [])

    file_exists("src/dest_app/web/post_handler.gleam") |> should.be_false
    file_exists("src/dest_app/data/post_repo.gleam") |> should.be_false
    file_contains("src/dest_app/router.gleam", "post_handler")
    |> should.be_false
    // The demo seed leaves the entry point with it.
    file_contains("src/dest_app.gleam", "post_repo") |> should.be_false
    file_contains("src/dest_app.gleam", "Demo data") |> should.be_false

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}

pub fn destroy_dry_run_writes_nothing_test() {
  in_temp_dir("destroy_dry", fn(dir) {
    let project_dir = dir <> "/dry_app"
    new.run(project_dir, ["--db", "sqlite"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_resource.resource("posts", ["title:string"])
    let assert Ok(before) = simplifile.read("src/dry_app/router.gleam")

    destroy.run("resource", "posts", ["--dry-run"])

    file_exists("src/dry_app/web/post_handler.gleam") |> should.be_true
    let assert Ok(after) = simplifile.read("src/dry_app/router.gleam")
    after |> should.equal(before)

    let assert Ok(_) = set_cwd(cwd)
    Nil
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
