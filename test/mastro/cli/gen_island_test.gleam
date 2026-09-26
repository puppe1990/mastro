/// Integration tests for `gen island`.
///
import gleeunit/should
import mastro/cli/cli_support.{
  current_directory, file_contains, file_exists, in_temp_dir, set_cwd,
}
import mastro/cli/gen/island as gen_island
import mastro/cli/new

pub fn gen_island_creates_files_test() {
  in_temp_dir("gen_island", fn(dir) {
    let project_dir = dir <> "/island_app"
    new.run(project_dir, [])

    let assert Ok(cwd) = current_directory()
    let assert Ok(_) = set_cwd(project_dir)

    gen_island.island("counter")

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
