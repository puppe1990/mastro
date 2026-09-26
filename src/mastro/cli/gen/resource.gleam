/// `gen resource <name> <fields...>` — CRUD files, routes and demo seed.
///
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/format
import mastro/cli/gen/demo_seed
import mastro/cli/gen/fields
import mastro/cli/gen/migration
import mastro/cli/gen/options
import mastro/cli/gen/resource_api
import mastro/cli/gen/resource_form
import mastro/cli/gen/resource_migration
import mastro/cli/gen/resource_repo
import mastro/cli/gen/resource_seed
import mastro/cli/gen/resource_tests
import mastro/cli/gen/resource_views
import mastro/cli/gen/router
import mastro/cli/project
import mastro/cli/templates
import mastro/cli/text
import mastro/cli/types.{BearerAuth, SessionAuth}
import simplifile

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
    True -> demo_seed.wire_demo_seed(app, singular, db)
    False -> []
  }
  let wired_paths = case options.admin_auth {
    BearerAuth ->
      list.append(wired_paths, demo_seed.patch_config_admin_routes(app))
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
