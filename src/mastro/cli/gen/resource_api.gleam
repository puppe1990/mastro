/// The generated JSON API handler and its params-only module.
///
import gleam/list
import gleam/string
import mastro/cli/gen/fields
import mastro/cli/templates
import mastro/cli/types.{
  type AdminAuth, type DbChoice, BearerAuth, SessionAuth, Sqlite,
}

pub fn api_params_module(
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

pub fn api_resource_handler(
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
