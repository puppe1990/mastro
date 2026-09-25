/// `mastro upgrade [version] [--dry-run]`
///
/// Bumps the mastro constraint in `gleam.toml`, prints the migration steps
/// for the operator, and runs `mastro doctor` — unless `--dry-run`, which
/// only reports what would change.
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mastro/cli/doctor
import simplifile

pub fn run(args: List(String)) {
  let dry_run = list.contains(args, "--dry-run")
  let version =
    args
    |> list.find(fn(arg) { !string.starts_with(arg, "--") })
    |> result.unwrap("latest")

  case simplifile.read("gleam.toml") {
    Error(_) -> io.println("No gleam.toml in this directory.")
    Ok(content) -> {
      let updated = set_framework_version(content, version)

      case dry_run {
        True -> {
          io.println("Would set mastro to >= " <> version <> " and < 1.0.0")
          io.println("Then: gleam deps download; mastro doctor")
        }
        False -> {
          case updated == content {
            True ->
              io.println("gleam.toml already constrains mastro to " <> version)
            False -> {
              let assert Ok(_) = simplifile.write("gleam.toml", updated)
              io.println("Updated mastro to >= " <> version <> " and < 1.0.0")
            }
          }
          io.println("")
          io.println("Migration steps:")
          list.each(steps(), io.println)
          io.println("")
          doctor.run([])
        }
      }
    }
  }
}

/// The constraint line the upgrade writes.
pub fn set_framework_version(content: String, version: String) -> String {
  let line = "mastro = \">= " <> version <> " and < 1.0.0\""
  content
  |> string.split("\n")
  |> list.map(fn(current) {
    case string.starts_with(string.trim(current), "mastro = ") {
      True -> line
      False -> current
    }
  })
  |> string.join("\n")
}

fn steps() -> List(String) {
  [
    "  gleam deps download",
    "  gleam test",
    "  mastro db status    # inspect pending migrations",
    "  mastro doctor       # verify the app still matches the contract",
  ]
}
