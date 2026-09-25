/// `mastro db` — database commands for the current project.
///
/// `status`, `rollback` and `prune-sessions` are answered by the generated
/// `src/<app>/migrate.gleam`; `seed` reuses the seed module.
///
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import mastro/cli/migrate_cmd
import mastro/cli/project
import mastro/cli/seed
import mastro/cli/types.{NoDb}
import simplifile

pub fn run(args: List(String)) {
  let app = project.app_name()

  case project.detect_db() {
    NoDb -> {
      io.println("No database configured.")
      io.println("Create a project with --db postgres or --db sqlite.")
    }
    db ->
      case args {
        [] -> print_help()
        ["seed", "--list", ..] -> list_seeds(app)
        ["seed", ..] -> seed.run()
        ["help", ..] | ["--help", ..] | ["-h", ..] -> print_help()
        _ -> migrate_cmd.run_command(app, db, args)
      }
  }
}

fn print_help() {
  io.println(string.join(
    [
      "mastro db — database commands",
      "",
      "Usage: mastro db <command>",
      "",
      "Commands:",
      "  status            List applied and pending migrations",
      "  rollback          Revert the most recent migration",
      "  prune-sessions    Delete expired sessions",
      "  seed              Run the project seeds",
      "    --list          List the seed helpers in the seed module",
    ],
    "\n",
  ))
}

fn list_seeds(app: String) {
  let path = "src/" <> app <> "/seed.gleam"

  case simplifile.read(path) {
    Error(_) -> {
      io.println("No seed module yet at " <> path)
      io.println("Run `mastro db seed` to create one.")
    }
    Ok(content) ->
      case helper_names(content) {
        [] -> {
          io.println("No seed helpers in " <> path)
          io.println(
            "Add `pub fn <name>()` next to main() to make seeds listable.",
          )
        }
        names -> {
          io.println("Seed helpers in " <> path <> ":")
          list.each(names, fn(name) { io.println("  " <> name) })
        }
      }
  }
}

fn helper_names(content: String) -> List(String) {
  content
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(string.trim(line), "pub fn ") {
      True ->
        case string.split(string.trim(line), "(") {
          [head, _] -> Ok(string.trim(string.drop_start(head, 7)))
          _ -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
  |> list.filter(fn(name) { name != "main" })
  |> list.unique
  |> list.sort(string.compare)
}
