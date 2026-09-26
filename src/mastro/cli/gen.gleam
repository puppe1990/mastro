/// Code generators: page, resource, migration, auth.
///
import gleam/dict
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/format
import mastro/cli/gen/fields
import mastro/cli/gen/gleam_file
import mastro/cli/gen/migration
import mastro/cli/gen/options
import mastro/cli/gen/resource_api
import mastro/cli/gen/resource_form
import mastro/cli/gen/resource_migration
import mastro/cli/gen/resource_references
import mastro/cli/gen/resource_repo
import mastro/cli/gen/resource_seed
import mastro/cli/gen/resource_tests
import mastro/cli/gen/resource_views
import mastro/cli/gen/router
import mastro/cli/gen/source
import mastro/cli/project
import mastro/cli/templates
import mastro/cli/text
import mastro/cli/types.{
  type AdminAuth, type DbChoice, BearerAuth, NoDb, Postgres, SessionAuth, Sqlite,
}
import simplifile

/// The comment the demo seed block in the entry point carries.
const demo_seed_marker = "  // Demo data for development"

// =============================================================================
// gen resource
// =============================================================================

pub fn resource(name: String, raw_args: List(String)) {
  let app = project.app_name()
  let db = project.detect_db()
  let api_mode = list.contains(raw_args, "--api")
  let options = options.parse_resource_options(raw_args)
  let belongs_to = options.flag_value(raw_args, "--belongs-to")
  let raw_fields = list.filter(raw_args, fn(a) { !string.starts_with(a, "--") })
  let singular = text.singularize(name)
  let type_name = text.capitalize(singular)

  // `field:references` and `field:belongs_to` become `<field>_id` columns
  // backed by a foreign key; `--belongs-to` is the older single-FK spelling.
  let parsed = fields.parse_fields(raw_fields)
  let references =
    parsed
    |> list.filter_map(fn(f) {
      case f.1 {
        "references" | "belongs_to" -> Ok(text.singularize(f.0))
        _ -> Error(Nil)
      }
    })
    |> list.append(case belongs_to {
      Ok(parent) -> [text.singularize(parent)]
      Error(_) -> []
    })

  let scalar_fields =
    parsed
    |> list.filter(fn(f) { f.1 != "references" && f.1 != "belongs_to" })
  let reference_fields =
    references |> list.map(fn(parent) { #(parent <> "_id", "int") })
  let fields = list.append(scalar_fields, reference_fields)

  // A reference whose parent was never generated has no repo to seed: the
  // demo seed would not compile, so it is skipped with a note.
  let parent_has_repo = fn(parent: String) {
    resource_seed.parent_repo_exists(app, parent)
  }
  let seed = options.seed && list.all(references, parent_has_repo)
  let missing_parents = case options.seed {
    True ->
      references
      |> list.unique
      |> list.filter(fn(parent) { !parent_has_repo(parent) })
    False -> []
  }

  // Sortable columns: the scalar fields the index shows. The display field
  // (search target) is the first one.
  let sortable = list.map(scalar_fields, fn(f) { f.0 })
  let display_field = case sortable {
    [first, ..] -> first
    [] -> "id"
  }

  // Paths
  let handler_path = "src/" <> app <> "/web/" <> singular <> "_handler.gleam"
  let views_path = "src/" <> app <> "/web/" <> singular <> "_views.gleam"
  let form_path = "src/" <> app <> "/web/forms/" <> singular <> "_form.gleam"
  let domain_path = "src/" <> app <> "/domain/" <> singular <> ".gleam"
  let repo_path = "src/" <> app <> "/data/" <> singular <> "_repo.gleam"
  let migration_path =
    "src/"
    <> app
    <> "/data/migrations/"
    <> migration.next_migration_number(app)
    <> "_create_"
    <> name
    <> ".sql"
  let test_path = "test/" <> app <> "/web/" <> singular <> "_handler_test.gleam"

  // Ensure directories
  list.each(
    [
      "src/" <> app <> "/web/forms",
      "src/" <> app <> "/domain",
      "src/" <> app <> "/data",
      "src/" <> app <> "/data/migrations",
      "test/" <> app <> "/web",
    ],
    fn(dir) {
      let _ = simplifile.create_directory_all(dir)
    },
  )

  // Generate files
  let first_field = case fields {
    [#(name, _), ..] -> name
    [] -> "id"
  }

  let gleam_fields =
    list.map(fields, fn(f) {
      let #(field_name, field_type) = f
      #(field_name, fields.to_gleam_type(field_type))
    })

  // Generate handler (HTML or JSON)
  let assert Ok(_) = case api_mode {
    True ->
      simplifile.write(
        handler_path,
        resource_api.api_resource_handler(
          app,
          name,
          singular,
          type_name,
          db,
          fields,
          options.admin_auth,
        ),
      )
    False ->
      simplifile.write(
        handler_path,
        templates.resource_handler(
          app,
          name,
          singular,
          type_name,
          first_field,
          db,
          options.public,
          options.admin_auth,
        ),
      )
  }

  // Views and forms: full for HTML, params-only for API
  let created_paths = case api_mode {
    False -> {
      let assert Ok(_) =
        simplifile.write(
          views_path,
          resource_views.resource_views(
            app,
            name,
            singular,
            type_name,
            fields,
            references,
            sortable,
            display_field,
            options,
          ),
        )
      let assert Ok(_) =
        simplifile.write(
          form_path,
          resource_form.resource_form(app, singular, type_name, fields),
        )
      [handler_path, views_path, form_path, domain_path, repo_path, test_path]
    }
    True -> {
      // API mode still needs the Params type for repos
      let assert Ok(_) =
        simplifile.write(
          form_path,
          resource_api.api_params_module(app, singular, type_name, fields),
        )
      [handler_path, form_path, domain_path, repo_path, test_path]
    }
  }

  let assert Ok(_) =
    simplifile.write(
      domain_path,
      templates.resource_domain_type(type_name, gleam_fields),
    )

  let assert Ok(_) =
    simplifile.write(
      repo_path,
      resource_repo.resource_repo(
        app,
        singular,
        type_name,
        fields,
        db,
        references,
        sortable,
        display_field,
        seed,
      ),
    )

  let assert Ok(_) =
    simplifile.write(
      migration_path,
      resource_migration.resource_migration(name, fields, db, references),
    )

  let assert Ok(_) =
    simplifile.write(test_path, case api_mode {
      True -> resource_tests.api_resource_test(app, singular)
      False -> resource_tests.resource_test(app, singular, type_name, fields)
    })

  // Patch router and format
  let _ = case api_mode {
    True -> router.patch_api_resource(app, name, singular)
    False -> router.patch_resource(app, name, singular, options)
  }
  let router_path = "src/" <> app <> "/router.gleam"

  // Demo rows at boot (development only) and the production gate a bearer
  // admin route needs.
  let wired_paths = case seed {
    True -> wire_demo_seed(app, singular, db)
    False -> []
  }
  let wired_paths = case options.admin_auth {
    BearerAuth -> list.append(wired_paths, patch_config_admin_routes(app))
    SessionAuth -> wired_paths
  }

  format.format_files(list.append([router_path, ..created_paths], wired_paths))

  io.println("")
  io.println("Created:")
  io.println("  " <> handler_path)
  case api_mode {
    False -> {
      io.println("  " <> views_path)
      io.println("  " <> form_path)
    }
    True -> Nil
  }
  io.println("  " <> domain_path)
  io.println("  " <> repo_path)
  io.println("  " <> migration_path)
  io.println("  " <> test_path)
  io.println("")
  io.println("Updated:")
  list.each([router_path, ..wired_paths], fn(path) { io.println("  " <> path) })
  io.println("")
  io.println("Flags: " <> options.describe_options(options))
  let admin_auth = options.auth_label(options.admin_auth)
  io.println("Admin: /admin/" <> name <> " (" <> admin_auth <> ")")
  case options.public {
    True -> io.println("Public: /" <> name)
    False -> Nil
  }
  case references {
    [] -> Nil
    _ -> io.println("Foreign keys: " <> string.join(references, ", "))
  }
  case missing_parents {
    [] -> Nil
    _ -> {
      io.println("")
      io.println(
        "No demo seed: "
        <> string.join(missing_parents, ", ")
        <> " has no repo module yet.",
      )
      io.println(
        "Generate it first (mastro gen resource <parents> <fields>) and"
        <> " regenerate this resource for a demo row.",
      )
    }
  }
}

/// Wire the resource demo seed into the entry point: development boots once
/// with a row to look at, production never gets demo data.
fn wire_demo_seed(
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
fn patch_config_admin_routes(app: String) -> List(String) {
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
