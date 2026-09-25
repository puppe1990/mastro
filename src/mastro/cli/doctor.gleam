/// `mastro doctor [--mobile]` — check the app against the Amarra contract.
///
/// Reads a snapshot of the project and runs `mastro/doctor` over it, then
/// prints one line per check. Exit code 1 when anything failed.
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import mastro/doctor
import simplifile

@external(erlang, "mastro_doctor_ffi", "halt")
fn halt(code: Int) -> Nil

pub fn run(args: List(String)) {
  let mobile = list.contains(args, "--mobile")
  let report = doctor.run(snapshot(), mobile)

  io.println(case mobile {
    True -> "mastro doctor --mobile"
    False -> "mastro doctor"
  })
  io.println("")

  list.each(report.checks, fn(check) {
    io.println(
      "  ["
      <> doctor.symbol(check.level)
      <> "] "
      <> check.name
      <> ": "
      <> check.message,
    )
  })

  let failures = doctor.failures(report)
  let warnings = doctor.warnings(report)

  io.println("")
  io.println(
    int.to_string(list.length(failures))
    <> " failed, "
    <> int.to_string(list.length(warnings))
    <> " warning(s)",
  )

  case doctor.has_failures(report) {
    True -> halt(1)
    False -> Nil
  }
}

fn snapshot() -> dict.Dict(String, String) {
  list.flatten([
    files_under("src"),
    files_under("priv"),
    ["gleam.toml", "manifest.toml"],
  ])
  |> list.fold(dict.new(), fn(acc, path) {
    dict.insert(acc, path, simplifile.read(path) |> result.unwrap(""))
  })
}

fn files_under(dir: String) -> List(String) {
  simplifile.get_files(dir) |> result.unwrap([])
}
