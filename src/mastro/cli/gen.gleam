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
import mastro/cli/gen/resource_repo
import mastro/cli/gen/resource_seed
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
        api_resource_handler(
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
          resource_views(
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
          resource_form(app, singular, type_name, fields),
        )
      [handler_path, views_path, form_path, domain_path, repo_path, test_path]
    }
    True -> {
      // API mode still needs the Params type for repos
      let assert Ok(_) =
        simplifile.write(
          form_path,
          api_params_module(app, singular, type_name, fields),
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
      resource_migration(name, fields, db, references),
    )

  let assert Ok(_) =
    simplifile.write(test_path, case api_mode {
      True -> api_resource_test(app, singular)
      False -> resource_test(app, singular, type_name, fields)
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

// =============================================================================
// Resource template helpers
// =============================================================================

fn api_params_module(
  _app_name: String,
  _resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let params_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> fields.to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  "/// Params type for " <> type_name <> " (API mode).
///
pub type " <> type_name <> "Params {
  " <> type_name <> "Params(
" <> params_field_defs <> "
  )
}
"
}

fn api_resource_handler(
  app_name: String,
  _resource_plural: String,
  resource_singular: String,
  type_name: String,
  db: DbChoice,
  fields: List(#(String, String)),
  admin_auth: AdminAuth,
) -> String {
  let db_arg = case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
  let auth_imports = case admin_auth {
    SessionAuth -> ""
    BearerAuth -> "\nimport " <> app_name <> "/config\nimport mastro/security"
  }

  // Build JSON object fields for serialization
  let json_fields =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let json_fn = case field_type {
        "int" -> "json.int"
        "float" -> "json.float"
        "bool" -> "json.bool"
        _ -> "json.string"
      }
      "      #(\"" <> name <> "\", " <> json_fn <> "(item." <> name <> ")),"
    })
    |> string.join("\n")

  let to_json =
    "fn to_json(item: "
    <> resource_singular
    <> ".type_placeholder) -> json.Json {
  json.object([
    #(\"id\", json.int(item.id)),
"
    <> json_fields
    <> "
  ])
}"

  // Fix the type placeholder
  let to_json = string.replace(to_json, "type_placeholder", type_name)

  let extra_imports = case list.any(fields, fn(f) { f.1 == "float" }) {
    True -> "\nimport gleam/float"
    False -> ""
  }

  "import gleam/dict" <> extra_imports <> "
import gleam/json
import " <> app_name <> "/context.{type Context}
import " <> app_name <> "/data/" <> resource_singular <> "_repo
import " <> app_name <> "/domain/" <> resource_singular <> "
import mastro/query
import wisp.{type Request, type Response}" <> auth_imports <> "

" <> templates.auth_guard(admin_auth, True) <> "
pub fn index(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  let params = query.parse(req.query)
  let q = dict.get(params, \"q\") |> result.unwrap(\"\")
  let sort = dict.get(params, \"sort\") |> result.unwrap(\"\")
  let dir = dict.get(params, \"dir\") |> result.unwrap(\"\")
  let page =
    dict.get(params, \"page\")
    |> result.try(int.parse)
    |> result.unwrap(1)

  let items = " <> resource_singular <> "_repo.list(" <> db_arg <> ", q, sort, dir, page)
  let body =
    json.array(items, to_json)
    |> json.to_string
  wisp.json_response(body, 200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  case int.parse(id) {
    Error(_) -> wisp.json_response(\"{\\\"error\\\":\\\"not found\\\"}\", 404)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(" <> db_arg <> ", id) {
        Error(_) -> wisp.json_response(\"{\\\"error\\\":\\\"not found\\\"}\", 404)
        Ok(item) -> {
          wisp.json_response(json.to_string(to_json(item)), 200)
        }
      }
  }
}

pub fn create(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  use _json_body <- wisp.require_json(req)
  // TODO: decode JSON body into " <> type_name <> "Params and create
  wisp.json_response(\"{\\\"error\\\":\\\"not implemented\\\"}\", 501)
}

pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  use _json_body <- wisp.require_json(req)
  // TODO: decode JSON body into " <> type_name <> "Params and update
  wisp.json_response(\"{\\\"error\\\":\\\"not implemented\\\"}\", 501)
}

pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  case int.parse(id) {
    Error(_) -> wisp.json_response(\"{\\\"error\\\":\\\"not found\\\"}\", 404)
    Ok(id) -> {
      let _ = " <> resource_singular <> "_repo.delete(" <> db_arg <> ", id)
      wisp.json_response(\"{\\\"ok\\\":true}\", 200)
    }
  }
}

" <> to_json <> "
"
}

fn resource_views(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  references: List(String),
  sortable: List(String),
  display_field: String,
  options: options.ResourceOptions,
) -> String {
  let first_field = case fields {
    [#(name, _), ..] -> name
    [] -> "id"
  }
  let admin_base = "/admin/" <> resource_plural

  let form_field_elements =
    fields
    |> list.map(fn(f) {
      let #(fname, ftype) = f
      let label_text = source.field_label(fname)
      case ftype {
        "bool" -> "      div([class(\"field\")], [
        label([], [
          input([type_(\"checkbox\"), name(\"" <> fname <> "\"), attribute.checked(values." <> fname <> ")]),
          text(\" " <> label_text <> "\"),
        ]),
      ]),"
        "text" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        textarea([name(\"" <> fname <> "\")], values." <> fname <> "),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "int" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(int.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "float" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(float.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        _ -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"text\"), name(\"" <> fname <> "\"), value(values." <> fname <> ")]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
      }
    })
    |> string.join("\n")

  let float_import = case list.any(fields, fn(f) { f.1 == "float" }) {
    True -> "\nimport gleam/float"
    False -> ""
  }
  let bool_import = case list.any(fields, fn(f) { f.1 == "bool" }) {
    True -> "\nimport gleam/bool"
    False -> ""
  }
  let html_imports = case list.any(fields, fn(f) { f.1 == "text" }) {
    True -> "a, button, div, form, h1, input, label, p, section, textarea,"
    False -> "a, button, div, form, h1, input, label, p, section,"
  }

  let columns =
    fields
    |> list.map(fn(f) {
      let #(fname, _) = f
      "    kit.Column(field: \""
      <> fname
      <> "\", label: \""
      <> source.field_label(fname)
      <> "\", sortable: "
      <> source.bool_literal(list.contains(sortable, fname))
      <> "),"
    })
    |> string.join("\n")

  let row_cells =
    fields
    |> list.index_map(fn(f, index) {
      let #(fname, ftype) = f
      let value = source.field_to_text(ftype, "item." <> fname)
      let content = case index {
        0 ->
          "a([href(\""
          <> admin_base
          <> "/\" <> int.to_string(item.id))], [text("
          <> value
          <> ")])"
        _ -> "text(" <> value <> ")"
      }
      "        html.td([], [" <> content <> "]),"
    })
    |> string.join("\n")

  // The public list is a label plus the numbers and flags of each row: the
  // long text fields stay out of a listing.
  let public_meta =
    fields
    |> list.filter(fn(f) {
      let #(fname, ftype) = f
      fname != display_field
      && !resource_seed.is_reference(fname, references)
      && { ftype == "int" || ftype == "float" || ftype == "bool" }
    })
    |> list.map(fn(f) {
      let #(fname, ftype) = f
      "            html.span([], [text(\""
      <> source.field_label(fname)
      <> ": \"), text("
      <> source.field_to_text(ftype, "item." <> fname)
      <> ")]),"
    })
    |> string.join("\n")

  let public_meta_block = case public_meta {
    "" -> ""
    _ -> "
            html.div([class(\"item-meta\")], [
" <> public_meta <> "
            ]),"
  }

  let display_text = case list.find(fields, fn(f) { f.0 == display_field }) {
    Ok(#(_, ftype)) -> source.field_to_text(ftype, "item." <> display_field)
    Error(_) -> "int.to_string(item.id)"
  }

  let public_view = case options.public {
    False -> ""
    True -> "
/// Public list: the search box and the page links, no admin links.
pub fn public_index_view(
  items: List(" <> type_name <> "),
  q: String,
  page: Int,
  pages: Int,
) -> Element(Nil) {
  section([class(\"" <> resource_plural <> "\")], [
    h1([], [text(\"" <> type_name <> "s\")]),
    kit.filters(\"/" <> resource_plural <> "\", input([name(\"q\"), value(q)])),
    case items {
      [] ->
        kit.empty_state([#(\"title\", \"No " <> type_name <> "s yet\")], text(\"\"))
      _ ->
        html.ul([class(\"" <> resource_singular <> "-list\")], list.map(items, fn(item) {
          html.li([], [
            html.p([class(\"item-title\")], [text(" <> display_text <> ")])," <> public_meta_block <> "
          ])
        }))
    },
    case pages > 1 {
      True ->
        kit.pagination(
          query.url(\"/" <> resource_plural <> "\", [#(\"q\", q)]),
          page,
          pages,
        )
      False -> text(\"\")
    },
  ])
}
"
  }

  "import gleam/int" <> float_import <> bool_import <> "
import gleam/list
import gleam/option
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{" <> html_imports <> "}
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import mastro/csrf
import mastro/kit
import mastro/query

/// Admin index: a search on " <> display_field <> ", a whitelisted sort and
/// one page of rows.
pub fn index_view(
  items: List(" <> type_name <> "),
  q: String,
  sort: String,
  dir: String,
  page: Int,
  pages: Int,
) -> Element(Nil) {
  let columns = [
" <> columns <> "
  ]
  let rows =
    list.map(items, fn(item) {
      html.tr([], [
" <> row_cells <> "
      ])
    })

  section([class(\"" <> resource_plural <> "\")], [
    div([class(\"header\")], [
      h1([], [text(\"" <> type_name <> "s\")]),
      a(
        [href(\"" <> admin_base <> "/new\"), class(\"btn\")],
        [text(\"New " <> type_name <> "\")],
      ),
    ]),
    kit.filters(\"" <> admin_base <> "\", html.div([class(\"filters-fields\")], [
      input([type_(\"hidden\"), name(\"sort\"), value(sort)]),
      input([type_(\"hidden\"), name(\"dir\"), value(dir)]),
      input([name(\"q\"), value(q)]),
    ])),
    case items {
      [] ->
        kit.empty_state(
          [#(\"title\", \"No " <> type_name <> "s yet\")],
          a([href(\"" <> admin_base <> "/new\")], [text(\"Create the first one\")]),
        )
      _ ->
        kit.table(
          columns,
          rows,
          query.url(\"" <> admin_base <> "\", [#(\"q\", q)]),
          sort,
          dir,
        )
    },
    case pages > 1 {
      True ->
        kit.pagination(
          query.url(\"" <> admin_base <> "\", [
            #(\"q\", q),
            #(\"sort\", sort),
            #(\"dir\", dir),
          ]),
          page,
          pages,
        )
      False -> text(\"\")
    },
  ])
}

pub fn show_view(item: " <> type_name <> ") -> Element(Nil) {
  section([class(\"" <> resource_singular <> "\")], [
    h1([], [text(item." <> first_field <> ")]),
    div([class(\"actions\")], [
      a(
        [
          href(\"" <> admin_base <> "/\" <> int.to_string(item.id) <> \"/edit\"),
          class(\"btn\"),
        ],
        [text(\"Edit\")],
      ),
    ]),
  ])
}

pub fn form_view(
  values: " <> resource_singular <> "_form." <> type_name <> "Form,
  errors: List(#(String, String)),
  csrf_token: String,
) -> Element(Nil) {
  let post_action = case values.id {
    option.Some(id) -> \"" <> admin_base <> "/\" <> int.to_string(id)
    option.None -> \"" <> admin_base <> "\"
  }

  section([class(\"" <> resource_singular <> "-form\")], [
    h1([], [text(case values.id {
      option.Some(_) -> \"Edit " <> type_name <> "\"
      option.None -> \"New " <> type_name <> "\"
    })]),
    form([attribute.action(post_action), attribute.method(\"post\")], [
      csrf.hidden_field(csrf_token),
      case values.id {
        option.Some(_) -> input([type_(\"hidden\"), name(\"_method\"), value(\"put\")])
        option.None -> text(\"\")
      },
" <> form_field_elements <> "
      button([type_(\"submit\"), class(\"btn\")], [text(\"Save\")]),
    ]),
  ])
}

fn field_error(
  errors: List(#(String, String)),
  field: String,
) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class(\"error\")], [text(message)])
    Error(_) -> text(\"\")
  }
}
" <> public_view
}

fn resource_form(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      let default_value = fields.form_default_value(field_type)
      "    " <> field_name <> ": " <> default_value <> ","
    })
    |> string.join("\n")

  let form_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> fields.to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let params_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> fields.to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let from_form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      case field_type {
        "bool" ->
          "    "
          <> field_name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> field_name
          <> "\" }),"
        "int" ->
          "    "
          <> field_name
          <> ": result.unwrap(int.parse(get_value(data, \""
          <> field_name
          <> "\")), 0),"
        "float" ->
          "    "
          <> field_name
          <> ": result.unwrap(float.parse(get_value(data, \""
          <> field_name
          <> "\")), 0.0),"
        _ ->
          "    " <> field_name <> ": get_value(data, \"" <> field_name <> "\"),"
      }
    })
    |> string.join("\n")

  let from_record_fields =
    fields
    |> list.map(fn(f) {
      let #(name, _) = f
      "    " <> name <> ": item." <> name <> ","
    })
    |> string.join("\n")

  let decode_lets =
    fields
    |> list.filter(fn(f) { f.1 != "bool" })
    |> list.map(fn(f) {
      let #(name, _) = f
      "  let " <> name <> " = get_value(data, \"" <> name <> "\")"
    })
    |> string.join("\n")

  let validation_lines =
    fields
    |> list.filter(fn(f) {
      let #(_, t) = f
      t == "string" || t == "text"
    })
    |> list.map(fn(f) {
      let #(name, _) = f
      "    |> validate.required("
      <> name
      <> ", \""
      <> name
      <> "\", \""
      <> text.capitalize(name)
      <> " is required\")"
    })
    |> string.join("\n")

  let params_construction =
    fields
    |> list.map(fn(f) {
      let #(name, t) = f
      case t {
        "bool" ->
          "        "
          <> name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> name
          <> "\" }),"
        "int" ->
          "        " <> name <> ": result.unwrap(int.parse(" <> name <> "), 0),"
        "float" ->
          "        "
          <> name
          <> ": result.unwrap(float.parse("
          <> name
          <> "), 0.0),"
        _ -> "        " <> name <> ": " <> name <> ","
      }
    })
    |> string.join("\n")

  let extra_imports = case
    list.any(fields, fn(f) { f.1 == "int" }),
    list.any(fields, fn(f) { f.1 == "float" })
  {
    True, True -> "\nimport gleam/int\nimport gleam/float"
    True, False -> "\nimport gleam/int"
    False, True -> "\nimport gleam/float"
    False, False -> ""
  }

  "import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result" <> extra_imports <> "
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import mastro/validate
import wisp

pub type " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Option(Int),
" <> form_field_defs <> "
  )
}

pub type " <> type_name <> "Params {
  " <> type_name <> "Params(
" <> params_field_defs <> "
  )
}

pub fn empty() -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> form_fields <> "
  )
}

pub fn from_" <> resource_singular <> "(item: " <> type_name <> ") -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Some(item.id),
" <> from_record_fields <> "
  )
}

pub fn from_form_data(data: wisp.FormData) -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> from_form_fields <> "
  )
}

pub fn decode(
  data: wisp.FormData,
) -> Result(" <> type_name <> "Params, List(#(String, String))) {
" <> decode_lets <> "

  let errors =
    []
" <> validation_lines <> "

  case errors {
    [] ->
      Ok(" <> type_name <> "Params(
" <> params_construction <> "
      ))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap(\"\")
}
"
}

fn resource_migration(
  name: String,
  fields: List(#(String, String)),
  db: DbChoice,
  references: List(String),
) -> String {
  let reference_tables =
    dict.from_list(
      references
      |> list.map(fn(parent) { #(parent <> "_id", parent <> "s") }),
    )

  let column_defs =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      case dict.get(reference_tables, field_name) {
        Ok(parent_table) ->
          "  "
          <> field_name
          <> " INTEGER NOT NULL REFERENCES "
          <> parent_table
          <> "(id)"
        Error(_) -> {
          let sql_type = case db {
            Sqlite -> fields.to_sql_type_sqlite(field_type)
            _ -> fields.to_sql_type(field_type)
          }
          "  " <> field_name <> " " <> sql_type <> " NOT NULL"
        }
      }
    })
    |> string.join(",\n")

  let table = text.singularize(name) <> "s"

  case db {
    Sqlite -> "-- up
CREATE TABLE " <> table <> " (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
" <> column_defs <> ",
  inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
-- down
DROP TABLE " <> table <> ";
"
    _ -> "-- up
CREATE TABLE " <> table <> " (
  id SERIAL PRIMARY KEY,
" <> column_defs <> ",
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- down
DROP TABLE " <> table <> ";
"
  }
}

fn api_resource_test(_app_name: String, _resource_singular: String) -> String {
  "import gleeunit/should

pub fn placeholder_test() {
  // API handler tests require a running database.
  // Test your domain logic and JSON encoding instead.
  1 + 1
  |> should.equal(2)
}
"
}

fn resource_test(
  app_name: String,
  resource_singular: String,
  _type_name: String,
  fields: List(#(String, String)),
) -> String {
  // Build valid form data for decode test
  let valid_values =
    fields
    |> list.map(fn(f) {
      let #(name, ftype) = f
      let val = case ftype {
        "bool" -> "on"
        "int" -> "42"
        "float" -> "3.14"
        _ -> "test value"
      }
      "    #(\"" <> name <> "\", \"" <> val <> "\"),"
    })
    |> string.join("\n")

  // Find required string fields for missing-field test
  let required_fields =
    fields
    |> list.filter(fn(f) { f.1 == "string" || f.1 == "text" })

  let missing_field_test = case required_fields {
    [#(name, _), ..] -> "

pub fn decode_missing_" <> name <> "_returns_error_test() {
  let data =
    wisp.FormData(values: [], files: [])

  " <> resource_singular <> "_form.decode(data)
  |> should.be_error
}
"
    [] -> ""
  }

  "import gleeunit/should
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import wisp

pub fn empty_form_has_no_id_test() {
  let form = " <> resource_singular <> "_form.empty()
  form.id
  |> should.be_none
}

pub fn decode_valid_form_test() {
  let data =
    wisp.FormData(
      values: [
" <> valid_values <> "
      ],
      files: [],
    )

  " <> resource_singular <> "_form.decode(data)
  |> should.be_ok
}
" <> missing_field_test
}
