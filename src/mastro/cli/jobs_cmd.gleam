/// `mastro jobs` — the queue commands for the current project.
///
/// Creates `src/<app>/jobs.gleam`, a worker that shares the app's database,
/// then runs it with the given arguments.
///
import gleam/io
import gleam/string
import mastro/cli/format
import mastro/cli/project
import mastro/cli/templates/jobs.{module_postgres, module_sqlite}
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

@external(erlang, "mastro_build_ffi", "run_cmd")
fn run_cmd(cmd: String) -> String

pub fn run(args: List(String)) {
  let app = project.app_name()

  case project.detect_db() {
    NoDb -> {
      io.println("No database configured.")
      io.println("Create a project with --db postgres or --db sqlite.")
    }
    db -> {
      let _ = ensure_module(app, db)

      let command = case args {
        [] -> "gleam run -m " <> app <> "/jobs"
        _ -> "gleam run -m " <> app <> "/jobs -- " <> string.join(args, " ")
      }

      io.println(run_cmd(command))
    }
  }
}

/// Write the worker module when the project has none yet.
pub fn ensure_module(app: String, db: DbChoice) -> Bool {
  let path = "src/" <> app <> "/jobs.gleam"

  case simplifile.read(path) {
    Ok(_) -> False
    Error(_) -> {
      let content = case db {
        Postgres -> module_postgres(app)
        Sqlite -> module_sqlite(app)
        NoDb -> ""
      }

      let assert Ok(_) = simplifile.write(path, content)
      format.format_files([path])
      io.println("Created: " <> path)
      True
    }
  }
}
