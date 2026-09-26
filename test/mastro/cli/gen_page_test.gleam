/// Integration tests for `gen page`.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/page as gen_page
import mastro/cli/new

pub fn gen_page_creates_handler_and_patches_router_test() {
  in_temp_dir("gen_page", fn(dir) {
    let project_dir = dir <> "/page_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_page.page("about")

    file_exists("src/page_app/web/about_handler.gleam") |> should.be_true
    file_exists("test/page_app/web/about_handler_test.gleam") |> should.be_true
    file_contains("src/page_app/router.gleam", "about_handler")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}
