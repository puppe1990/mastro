/// `gen migration <name>` — a numbered SQL migration file.
///
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/project
import simplifile

pub fn migration(name: String) {
  let app = project.app_name()
  let dir = "src/" <> app <> "/data/migrations"
  let _ = simplifile.create_directory_all(dir)

  let number = next_migration_number(app)
  let filename = number <> "_" <> name <> ".sql"
  let path = dir <> "/" <> filename

  let content =
    "-- Migration: " <> name <> "\n" <> "-- up\n" <> "\n" <> "-- down\n" <> "\n"

  let assert Ok(_) = simplifile.write(path, content)

  io.println("")
  io.println("Created:")
  io.println("  " <> path)
}

/// Next free `NNN` prefix, from how many migrations already exist. Shared
/// with the resource generator, which writes its own migration file.
pub fn next_migration_number(app: String) -> String {
  let dir = "src/" <> app <> "/data/migrations"
  case simplifile.read_directory(dir) {
    Ok(files) -> {
      let count = list.length(files) + 1
      pad_number(count, 3)
    }
    Error(_) -> "001"
  }
}

fn pad_number(n: Int, width: Int) -> String {
  let s = int.to_string(n)
  let padding = width - string.length(s)
  case padding > 0 {
    True -> string.repeat("0", padding) <> s
    False -> s
  }
}
