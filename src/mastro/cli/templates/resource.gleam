/// File templates the resource generator shares: handler, guard, domain.
///
import gleam/string
import mastro/cli/types.{
  type AdminAuth, type DbChoice, BearerAuth, SessionAuth, Sqlite,
}

pub fn resource_handler(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  _first_field: String,
  db: DbChoice,
  public: Bool,
  admin_auth: AdminAuth,
) -> String {
  let db_arg = case db {
    Sqlite -> "ctx.db_path"
    _ -> "ctx.db"
  }
  let admin_base = "/admin/" <> resource_plural
  let auth_imports = case admin_auth {
    SessionAuth -> ""
    BearerAuth -> "\nimport " <> app_name <> "/config\nimport mastro/security"
  }

  let public_index = case public {
    False -> ""
    True -> "
/// The public list: the search box and the page links, nothing else.
pub fn public_index(req: Request, ctx: Context) -> Response {
  let params = query.parse(req.query)
  let q = dict.get(params, \"q\") |> result.unwrap(\"\")
  let page =
    dict.get(params, \"page\")
    |> result.try(int.parse)
    |> result.unwrap(1)

  let items = " <> resource_singular <> "_repo.list(" <> db_arg <> ", q, \"\", \"\", page)
  let pages =
    query.total_pages(" <> resource_singular <> "_repo.count(" <> db_arg <> ", q), query.per_page)

  " <> resource_singular <> "_views.public_index_view(items, q, page, pages)
  |> root_layout.wrap(\"" <> type_name <> "s\", req)
  |> wisp.html_response(200)
}
"
  }

  "import gleam/dict
import gleam/int
import gleam/option
import gleam/result
import " <> app_name <> "/context.{type Context}
import " <> app_name <> "/data/" <> resource_singular <> "_repo
import " <> app_name <> "/web/error_handler
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import " <> app_name <> "/web/layouts/root_layout
import " <> app_name <> "/web/" <> resource_singular <> "_views
import mastro/csrf
import mastro/flash
import mastro/query
import wisp.{type Request, type Response}" <> auth_imports <> "

" <> auth_guard(admin_auth, False) <> public_index <> "
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
  let pages =
    query.total_pages(" <> resource_singular <> "_repo.count(" <> db_arg <> ", q), query.per_page)

  " <> resource_singular <> "_views.index_view(items, q, sort, dir, page, pages)
  |> root_layout.wrap(\"" <> type_name <> "s\", req)
  |> wisp.html_response(200)
}

pub fn show(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(" <> db_arg <> ", id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          " <> resource_singular <> "_views.show_view(item)
          |> root_layout.wrap(\"" <> type_name <> "\", req)
          |> wisp.html_response(200)
      }
  }
}

pub fn new(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  " <> resource_singular <> "_views.form_view(
    " <> resource_singular <> "_form.empty(),
    [],
    csrf.token(req),
  )
  |> root_layout.wrap(\"New " <> type_name <> "\", req)
  |> wisp.html_response(200)
}

pub fn create(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))

  case " <> resource_singular <> "_form.decode(form_data) {
    Error(errors) ->
      " <> resource_singular <> "_views.form_view(
        " <> resource_singular <> "_form.from_form_data(form_data),
        errors,
        csrf.token(req),
      )
      |> root_layout.wrap(\"New " <> type_name <> "\", req)
      |> wisp.html_response(422)

    Ok(params) ->
      case " <> resource_singular <> "_repo.create(" <> db_arg <> ", params) {
        Ok(item) ->
          wisp.redirect(\"" <> admin_base <> "/\" <> int.to_string(item.id))
          |> flash.set_flash(req, \"info\", \"" <> type_name <> " created\")

        Error(_) -> error_handler.internal_error(req)
      }
  }
}

pub fn edit(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_repo.get(" <> db_arg <> ", id) {
        Error(_) -> error_handler.not_found(req)
        Ok(item) ->
          " <> resource_singular <> "_views.form_view(
            " <> resource_singular <> "_form.from_" <> resource_singular <> "(item),
            [],
            csrf.token(req),
          )
          |> root_layout.wrap(\"Edit " <> type_name <> "\", req)
          |> wisp.html_response(200)
      }
  }
}

pub fn update(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))

  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) ->
      case " <> resource_singular <> "_form.decode(form_data) {
        Error(errors) ->
          " <> resource_singular <> "_views.form_view(
            " <> resource_singular <> "_form.from_form_data(form_data),
            errors,
            csrf.token(req),
          )
          |> root_layout.wrap(\"Edit " <> type_name <> "\", req)
          |> wisp.html_response(422)

        Ok(params) ->
          case " <> resource_singular <> "_repo.update(" <> db_arg <> ", id, params) {
            Ok(_) ->
              wisp.redirect(\"" <> admin_base <> "/\" <> int.to_string(id))
              |> flash.set_flash(req, \"info\", \"" <> type_name <> " updated\")

            Error(_) -> error_handler.internal_error(req)
          }
      }
  }
}

pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  use <- require_admin(req, ctx)
  use <- csrf.require_request(req)

  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> {
      let _ = " <> resource_singular <> "_repo.delete(" <> db_arg <> ", id)
      wisp.redirect(\"" <> admin_base <> "\")
      |> flash.set_flash(req, \"info\", \"" <> type_name <> " deleted\")
    }
  }
}
"
}

/// The admin gate every generated action starts with. A JSON resource
/// answers a denial with `401` instead of a redirect.
pub fn auth_guard(mode: AdminAuth, api: Bool) -> String {
  let denied = case api {
    True -> "wisp.json_response(\"{\\\"error\\\":\\\"unauthorized\\\"}\", 401)"
    False ->
      case mode {
        SessionAuth -> "wisp.redirect(\"/login\")"
        BearerAuth -> "wisp.response(401)"
      }
  }

  let check = case mode {
    SessionAuth -> "case wisp.get_cookie(req, \"_user_id\", wisp.Signed) {
    Ok(_) -> next()
    Error(_) -> " <> denied <> "
  }"
    BearerAuth -> "case
    security.bearer_authorized(
      req,
      ctx.config.admin_token,
      config.is_production(ctx.config),
    )
  {
    True -> next()
    False -> " <> denied <> "
  }"
  }

  let doc = case mode {
    SessionAuth ->
      "/// Admin gate: the signed `_user_id` cookie the auth generator writes.
/// Swap in `auth.require_auth` when the handler needs the user row."
    BearerAuth ->
      "/// Admin gate: `ADMIN_TOKEN` in an `Authorization: Bearer` header.
/// An unset token opens the gate in development; production refuses to
/// boot without one (`config.validate`)."
  }

  let ctx_arg = case mode {
    SessionAuth -> "_ctx"
    BearerAuth -> "ctx"
  }

  doc <> "
fn require_admin(req: Request, " <> ctx_arg <> ": Context, next: fn() -> Response) -> Response {
  " <> check <> "
}

"
}

pub fn resource_domain_type(
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let field_defs =
    fields
    |> list_map_join(
      fn(field) {
        let #(name, gleam_type) = field
        "    " <> name <> ": " <> gleam_type <> ","
      },
      "\n",
    )

  "pub type " <> type_name <> " {
  " <> type_name <> "(
    id: Int,
" <> field_defs <> "
  )
}
"
}

// =============================================================================
// Helpers
// =============================================================================

fn list_map_join(
  items: List(a),
  f: fn(a) -> String,
  separator: String,
) -> String {
  items
  |> do_list_map_join(f, [])
  |> string.join(separator)
}

fn do_list_map_join(
  items: List(a),
  f: fn(a) -> String,
  acc: List(String),
) -> List(String) {
  case items {
    [] -> list_reverse(acc)
    [first, ..rest] -> do_list_map_join(rest, f, [f(first), ..acc])
  }
}

fn list_reverse(items: List(a)) -> List(a) {
  do_list_reverse(items, [])
}

fn do_list_reverse(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> do_list_reverse(rest, [first, ..acc])
  }
}
