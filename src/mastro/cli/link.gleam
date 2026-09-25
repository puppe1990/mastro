/// `mastro link [path] [--unlink]`
///
/// Points `gleam.toml` at a local checkout of the framework for development
/// (`mastro = { path = "../mastro" }`). This is a local-only change: do not
/// commit it. `--unlink` restores the published version constraint.
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub const published = "mastro = \">= 0.1.0 and < 1.0.0\""

pub fn run(args: List(String)) {
  let unlink = list.contains(args, "--unlink")
  let path =
    args
    |> list.find(fn(arg) { !string.starts_with(arg, "--") })
    |> result.unwrap("..")

  case simplifile.read("gleam.toml") {
    Error(_) -> io.println("No gleam.toml in this directory.")
    Ok(content) -> {
      let updated = case unlink {
        True -> remove_path_dependency(content)
        False -> set_path_dependency(content, path)
      }

      case updated == content {
        True -> io.println("gleam.toml is already up to date.")
        False -> {
          let assert Ok(_) = simplifile.write("gleam.toml", updated)
          case unlink {
            True ->
              io.println("Unlinked mastro (back to the published version).")
            False -> {
              io.println("Linked mastro to " <> path <> ".")
              io.println(
                "Do not commit this change; run `mastro link --unlink` first.",
              )
            }
          }
        }
      }
    }
  }
}

/// Replace the `mastro = ...` dependency line with a local path.
pub fn set_path_dependency(content: String, path: String) -> String {
  replace_dependency(content, "mastro = { path = \"" <> path <> "\" }")
}

/// Restore the published version constraint.
pub fn remove_path_dependency(content: String) -> String {
  replace_dependency(content, published)
}

fn replace_dependency(content: String, line: String) -> String {
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
