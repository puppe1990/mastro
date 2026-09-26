/// `mastro destroy resource|handler|model|migration|auth <name> [--dry-run]`
///
/// Removes generated files and undoes the router patches the generators
/// applied. `destroy migration` only deletes the `.sql` file — it never
/// touches the `schema_migrations` ledger, so an applied migration is not
/// silently forgotten.
///
/// `--dry-run` prints every change without writing.
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/format
import mastro/cli/project
import mastro/cli/text
import simplifile

pub fn run(kind: String, name: String, flags: List(String)) {
  let dry_run = list.contains(flags, "--dry-run")
  let app = project.app_name()

  case kind {
    "resource" -> destroy_resource(app, name, dry_run)
    "handler" -> destroy_handler(app, name, dry_run)
    "model" -> destroy_model(app, name, dry_run)
    "migration" -> destroy_migration(app, name, dry_run)
    "auth" -> destroy_auth(app, dry_run)
    _ ->
      io.println(
        "Usage: mastro destroy resource|handler|model|migration|auth <name> [--dry-run]",
      )
  }
}

fn destroy_resource(app: String, plural: String, dry_run: Bool) {
  let singular = text.singularize(plural)
  [
    "src/" <> app <> "/web/" <> singular <> "_handler.gleam",
    "src/" <> app <> "/web/" <> singular <> "_views.gleam",
    "src/" <> app <> "/web/forms/" <> singular <> "_form.gleam",
    "src/" <> app <> "/domain/" <> singular <> ".gleam",
    "src/" <> app <> "/data/" <> singular <> "_repo.gleam",
    "test/" <> app <> "/web/" <> singular <> "_handler_test.gleam",
  ]
  |> list.each(fn(path) { remove(path, dry_run) })

  remove_migrations(app, plural, False, dry_run)
  unroute(app, singular <> "_handler", dry_run)
  unwire_demo_seed(app, singular, dry_run)
}

/// Drop the resource's demo seed from the entry point: its import and its
/// line inside the development guard. The guard goes with the last line.
fn unwire_demo_seed(app: String, singular: String, dry_run: Bool) {
  let path = "src/" <> app <> ".gleam"
  case simplifile.read(path) {
    Error(_) -> Nil
    Ok(content) -> {
      let kept =
        content
        |> string.split("\n")
        |> list.filter(fn(line) {
          !string.contains(
            line,
            "import " <> app <> "/data/" <> singular <> "_repo",
          )
          && !string.contains(line, singular <> "_repo.seed_demo(")
        })
        |> string.join("\n")

      let kept = case string.contains(kept, ".seed_demo(") {
        True -> kept
        False -> remove_demo_seed_block(kept)
      }

      case kept == content {
        True -> Nil
        False ->
          case dry_run {
            True ->
              io.println(
                "would patch "
                <> path
                <> " (-"
                <> singular
                <> "_repo.seed_demo)",
              )
            False -> {
              let assert Ok(_) = simplifile.write(path, kept)
              format.format_files([path])
              io.println("patched " <> path)
            }
          }
      }
    }
  }
}

/// Remove the development seed guard once its last line is gone, so the
/// entry point does not keep an empty case behind.
fn remove_demo_seed_block(content: String) -> String {
  case string.split_once(content, "  // Demo data for development") {
    Error(_) -> content
    Ok(#(before, after)) ->
      case string.split_once(after, "\n  }\n") {
        Error(_) -> content
        Ok(#(_, rest)) -> before <> rest
      }
  }
}

fn destroy_handler(app: String, name: String, dry_run: Bool) {
  remove("src/" <> app <> "/web/" <> name <> "_handler.gleam", dry_run)
  remove("test/" <> app <> "/web/" <> name <> "_handler_test.gleam", dry_run)
  unroute(app, name <> "_handler", dry_run)
}

fn destroy_model(app: String, name: String, dry_run: Bool) {
  remove("src/" <> app <> "/domain/" <> name <> ".gleam", dry_run)
  remove("src/" <> app <> "/data/" <> name <> "_repo.gleam", dry_run)
}

fn destroy_migration(app: String, name: String, dry_run: Bool) {
  remove_migrations(app, name, True, dry_run)
}

fn destroy_auth(app: String, dry_run: Bool) {
  [
    "src/" <> app <> "/domain/user.gleam",
    "src/" <> app <> "/domain/auth.gleam",
    "src/" <> app <> "/data/user_repo.gleam",
    "src/" <> app <> "/web/auth_handler.gleam",
    "src/" <> app <> "/web/auth_views.gleam",
    "src/" <> app <> "/web/forms/auth_form.gleam",
    "src/" <> app <> "/web/middleware/auth.gleam",
  ]
  |> list.each(fn(path) { remove(path, dry_run) })

  unroute(app, "auth_handler", dry_run)
}

// -- Helpers ------------------------------------------------------------------

/// Remove migration files named `*_<name>.sql`. With `exact` the number
/// prefix is kept (`001_add_email.sql`); otherwise both `_posts.sql` and
/// `_post.sql` match, so a resource finds its `create_` migration.
fn remove_migrations(app: String, name: String, exact: Bool, dry_run: Bool) {
  let singular = text.singularize(name)
  let dir = "src/" <> app <> "/data/migrations"

  case simplifile.get_files(dir) {
    Error(_) -> Nil
    Ok(files) ->
      files
      |> list.filter(fn(path) {
        let matches = string.ends_with(path, "_" <> name <> ".sql")
        case exact {
          True -> matches
          False -> matches || string.ends_with(path, "_" <> singular <> ".sql")
        }
      })
      |> list.each(fn(path) { remove(path, dry_run) })
  }
}

fn remove(path: String, dry_run: Bool) {
  case simplifile.read(path) {
    Error(_) -> Nil
    Ok(_) ->
      case dry_run {
        True -> io.println("would remove " <> path)
        False -> {
          let _ = simplifile.delete_file(path)
          io.println("removed " <> path)
        }
      }
  }
}

fn unroute(app: String, fragment: String, dry_run: Bool) {
  let path = "src/" <> app <> "/router.gleam"
  case simplifile.read(path) {
    Error(_) -> Nil
    Ok(content) -> {
      let kept =
        content
        |> string.split("\n")
        |> drop_routes(fragment, [])
        |> string.join("\n")

      case kept == content {
        True -> Nil
        False ->
          case dry_run {
            True ->
              io.println("would patch " <> path <> " (-" <> fragment <> ")")
            False -> {
              let assert Ok(_) = simplifile.write(path, kept)
              format.format_files([path])
              io.println("patched " <> path)
            }
          }
      }
    }
  }
}

/// Drop every line carrying the fragment, and the pattern line a long route
/// left behind: the formatter wraps
/// `["posts", id, "edit"], http.Get ->` and its handler onto two lines, and
/// only the handler carries the module name.
fn drop_routes(
  lines: List(String),
  fragment: String,
  kept: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(kept)
    [line, ..rest] ->
      case string.contains(line, fragment) {
        False -> drop_routes(rest, fragment, [line, ..kept])
        True -> drop_routes(rest, fragment, drop_pattern_line(kept))
      }
  }
}

fn drop_pattern_line(kept: List(String)) -> List(String) {
  case kept {
    [previous, ..remaining] ->
      case string.ends_with(string.trim(previous), "->") {
        True -> remaining
        False -> kept
      }
    [] -> kept
  }
}
