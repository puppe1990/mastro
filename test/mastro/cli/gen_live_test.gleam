/// Integration tests for `gen live`.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/live as gen_live
import mastro/cli/new

pub fn gen_live_creates_socket_and_handler_test() {
  in_temp_dir("gen_live", fn(dir) {
    let project_dir = dir <> "/live_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_live.live("counter")

    file_exists("src/live_app/web/live/counter.gleam") |> should.be_true
    file_exists("src/live_app/web/live/counter_socket.gleam")
    |> should.be_true
    file_exists("src/live_app/web/counter_live_handler.gleam")
    |> should.be_true

    file_contains(
      "src/live_app/web/live/counter_socket.gleam",
      "pub fn upgrade(",
    )
    |> should.be_true
    file_contains("src/live_app/router.gleam", "counter_live_handler")
    |> should.be_true

    let assert Ok(_) = set_cwd(cwd)
    Nil
  })
}
