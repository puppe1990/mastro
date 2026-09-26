/// Wiring the resource demo seed into the generated entry point's boot.
///
import gleam/string
import mastro/cli/gen/gleam_file
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}
import simplifile

/// The comment the demo seed block in the entry point carries.
const demo_seed_marker = "  // Demo data for development"

/// Wire the resource demo seed into the entry point: development boots once
/// with a row to look at, production never gets demo data.
pub fn wire_demo_seed(
  app: String,
  resource_singular: String,
  db: DbChoice,
) -> List(String) {
  case db {
    NoDb -> []
    Sqlite | Postgres -> {
      let path = "src/" <> app <> ".gleam"
      let assert Ok(content) = simplifile.read(path)
      let repo_module = app <> "/data/" <> resource_singular <> "_repo"
      let call = case db {
        Postgres -> "db"
        _ -> "db_path"
      }

      case string.contains(content, repo_module <> ".seed_demo(") {
        True -> []
        False -> {
          let seed_line =
            "      let _ = "
            <> resource_singular
            <> "_repo.seed_demo("
            <> call
            <> ")\n"
          let content = gleam_file.add_import(content, "import " <> repo_module)
          let content = add_demo_seed(content, seed_line)
          let assert Ok(_) = simplifile.write(path, content)
          [path]
        }
      }
    }
  }
}

/// The demo guard the entry point carries: seeded once at boot in
/// development, never in production. The first resource adds the block; the
/// next ones add their line to it.
fn add_demo_seed(content: String, seed_line: String) -> String {
  case string.split_once(content, demo_seed_marker) {
    Error(_) -> insert_before_ctx(content, demo_seed_block(seed_line))
    Ok(#(before, after)) ->
      case string.split_once(after, "\n" <> demo_seed_after) {
        Ok(#(branch, rest)) ->
          before
          <> demo_seed_marker
          <> branch
          <> "\n"
          <> seed_line
          <> demo_seed_after
          <> rest
        Error(_) -> content
      }
  }
}

/// Everything after the last seed line of the block, so a new line lands
/// above the `Nil` that closes the branch.
const demo_seed_after = "      Nil\n    }\n    False -> Nil"

fn demo_seed_block(seed_line: String) -> String {
  demo_seed_marker <> ": each resource seeds once, when its table is empty.
  case config.is_development(cfg) {
    True -> {
" <> seed_line <> demo_seed_after <> "
  }
"
}

fn insert_before_ctx(content: String, block: String) -> String {
  case string.split_once(content, "\n  let ctx = context.Context(") {
    Ok(#(before, after)) ->
      before <> "\n" <> block <> "  let ctx = context.Context(" <> after
    Error(_) -> content
  }
}

/// A bearer admin route makes `ADMIN_TOKEN` mandatory in production, so the
/// boot gate has to know the app serves one.
pub fn patch_config_admin_routes(app: String) -> List(String) {
  let path = "src/" <> app <> "/config.gleam"
  let assert Ok(content) = simplifile.read(path)
  let patched =
    string.replace(content, "admin_routes: False", "admin_routes: True")

  case patched == content {
    True -> []
    False -> {
      let assert Ok(_) = simplifile.write(path, patched)
      [path]
    }
  }
}
