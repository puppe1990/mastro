/// Integration tests for `gen auth`.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/auth as gen_auth
import mastro/cli/new

pub fn gen_auth_creates_all_files_test() {
  in_temp_dir("gen_auth", fn(dir) {
    let project_dir = dir <> "/auth_app"
    new.run(project_dir, ["--db", "postgres"])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_auth.auth()

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
