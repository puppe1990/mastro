/// Templates for the auth generator's form, handler, views and middleware.
///
pub fn auth_form(_app: String) -> String {
  "import gleam/list
import gleam/result
import mastro/validate
import wisp

pub type LoginParams {
  LoginParams(email: String, password: String)
}

pub type RegisterParams {
  RegisterParams(email: String, password: String, password_confirmation: String)
}

pub fn decode_login(
  data: wisp.FormData,
) -> Result(LoginParams, List(#(String, String))) {
  let email = get_value(data, \"email\")
  let password = get_value(data, \"password\")

  let errors =
    []
    |> validate.required(email, \"email\", \"Email is required\")
    |> validate.required(password, \"password\", \"Password is required\")

  case errors {
    [] -> Ok(LoginParams(email: email, password: password))
    _ -> Error(errors)
  }
}

pub fn decode_register(
  data: wisp.FormData,
) -> Result(RegisterParams, List(#(String, String))) {
  let email = get_value(data, \"email\")
  let password = get_value(data, \"password\")
  let password_confirmation = get_value(data, \"password_confirmation\")

  let errors =
    []
    |> validate.required(email, \"email\", \"Email is required\")
    |> validate.required(password, \"password\", \"Password is required\")
    |> validate.min_length(password, \"password\", 8, \"Password must be at least 8 characters\")
    |> check_confirmation(password, password_confirmation)

  case errors {
    [] ->
      Ok(RegisterParams(
        email: email,
        password: password,
        password_confirmation: password_confirmation,
      ))
    _ -> Error(errors)
  }
}

fn check_confirmation(
  errors: List(#(String, String)),
  password: String,
  confirmation: String,
) -> List(#(String, String)) {
  case password == confirmation {
    True -> errors
    False -> [#(\"password_confirmation\", \"Passwords do not match\"), ..errors]
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap(\"\")
}
"
}

pub fn auth_handler(app: String) -> String {
  "import gleam/int
import gleam/option
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/auth
import " <> app <> "/web/auth_views
import " <> app <> "/web/error_handler
import " <> app <> "/web/forms/auth_form
import " <> app <> "/web/layouts/root_layout
import mastro/csrf
import mastro/flash
import wisp.{type Request, type Response}

pub fn login_page(req: Request, _ctx: Context) -> Response {
  auth_views.login_view(\"\", [], csrf.token(req))
  |> root_layout.wrap(\"Log In\", req)
  |> wisp.html_response(200)
}

pub fn login(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))

  case auth_form.decode_login(form_data) {
    Error(errors) ->
      auth_views.login_view(\"\", errors, csrf.token(req))
      |> root_layout.wrap(\"Log In\", req)
      |> wisp.html_response(422)

    Ok(params) ->
      case user_repo.get_by_email(ctx.db, params.email) {
        Error(_) ->
          auth_views.login_view(
            params.email,
            [#(\"email\", \"Invalid email or password\")],
            csrf.token(req),
          )
          |> root_layout.wrap(\"Log In\", req)
          |> wisp.html_response(422)

        Ok(user) ->
          case auth.verify_password(params.password, user.hashed_password) {
            False ->
              auth_views.login_view(
                params.email,
                [#(\"email\", \"Invalid email or password\")],
                csrf.token(req),
              )
              |> root_layout.wrap(\"Log In\", req)
              |> wisp.html_response(422)

            True ->
              wisp.redirect(\"/\")
              |> wisp.set_cookie(
                req,
                \"_user_id\",
                int.to_string(user.id),
                wisp.Signed,
                60 * 60 * 24 * 7,
              )
              |> flash.set_flash(req, \"info\", \"Logged in\")
          }
      }
  }
}

pub fn register_page(req: Request, _ctx: Context) -> Response {
  auth_views.register_view(\"\", [], csrf.token(req))
  |> root_layout.wrap(\"Register\", req)
  |> wisp.html_response(200)
}

pub fn register(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))

  case auth_form.decode_register(form_data) {
    Error(errors) ->
      auth_views.register_view(\"\", errors, csrf.token(req))
      |> root_layout.wrap(\"Register\", req)
      |> wisp.html_response(422)

    Ok(params) -> {
      let hashed = auth.hash_password(params.password)
      case user_repo.create(ctx.db, params.email, hashed) {
        Ok(user) ->
          wisp.redirect(\"/\")
          |> wisp.set_cookie(
            req,
            \"_user_id\",
            int.to_string(user.id),
            wisp.Signed,
            60 * 60 * 24 * 7,
          )
          |> flash.set_flash(req, \"info\", \"Account created\")

        Error(_) ->
          auth_views.register_view(
            params.email,
            [#(\"email\", \"Could not create account\")],
            csrf.token(req),
          )
          |> root_layout.wrap(\"Register\", req)
          |> wisp.html_response(422)
      }
    }
  }
}

pub fn logout(req: Request, _ctx: Context) -> Response {
  wisp.redirect(\"/\")
  |> wisp.set_cookie(req, \"_user_id\", \"\", wisp.Signed, 0)
  |> flash.set_flash(req, \"info\", \"Logged out\")
}
"
}

pub fn auth_views(_app: String) -> String {
  "import gleam/list
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, input, label, p, section,
}
import mastro/csrf

pub fn login_view(
  email: String,
  errors: List(#(String, String)),
  csrf_token: String,
) -> Element(Nil) {
  section([class(\"auth-form\")], [
    h1([], [text(\"Log In\")]),
    form([attribute.action(\"/login\"), attribute.method(\"post\")], [
      csrf.hidden_field(csrf_token),
      div([class(\"field\")], [
        label([], [text(\"Email\")]),
        input([type_(\"email\"), name(\"email\"), value(email)]),
        field_error(errors, \"email\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Password\")]),
        input([type_(\"password\"), name(\"password\")]),
        field_error(errors, \"password\"),
      ]),
      button([type_(\"submit\"), class(\"btn\")], [text(\"Log In\")]),
    ]),
    p([], [
      text(\"Don't have an account? \"),
      a([href(\"/register\")], [text(\"Register\")]),
    ]),
  ])
}

pub fn register_view(
  email: String,
  errors: List(#(String, String)),
  csrf_token: String,
) -> Element(Nil) {
  section([class(\"auth-form\")], [
    h1([], [text(\"Register\")]),
    form([attribute.action(\"/register\"), attribute.method(\"post\")], [
      csrf.hidden_field(csrf_token),
      div([class(\"field\")], [
        label([], [text(\"Email\")]),
        input([type_(\"email\"), name(\"email\"), value(email)]),
        field_error(errors, \"email\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Password\")]),
        input([type_(\"password\"), name(\"password\")]),
        field_error(errors, \"password\"),
      ]),
      div([class(\"field\")], [
        label([], [text(\"Confirm Password\")]),
        input([type_(\"password\"), name(\"password_confirmation\")]),
        field_error(errors, \"password_confirmation\"),
      ]),
      button([type_(\"submit\"), class(\"btn\")], [text(\"Register\")]),
    ]),
    p([], [
      text(\"Already have an account? \"),
      a([href(\"/login\")], [text(\"Log In\")]),
    ]),
  ])
}

fn field_error(errors: List(#(String, String)), field: String) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class(\"error\")], [text(message)])
    Error(_) -> text(\"\")
  }
}
"
}

pub fn auth_middleware(app: String) -> String {
  "import gleam/int
import gleam/result
import " <> app <> "/context.{type Context}
import " <> app <> "/data/user_repo
import " <> app <> "/domain/user.{type User}
import wisp.{type Request, type Response}

/// Extract the current user from the session cookie.
pub fn get_current_user(req: Request, ctx: Context) -> Result(User, Nil) {
  use user_id_str <- result.try(wisp.get_cookie(req, \"_user_id\", wisp.Signed))
  use user_id <- result.try(
    int.parse(user_id_str)
    |> result.replace_error(Nil),
  )
  user_repo.get_by_id(ctx.db, user_id)
}

/// Middleware that requires authentication.
/// Redirects to /login if no valid session.
pub fn require_auth(
  req: Request,
  ctx: Context,
  next: fn(User) -> Response,
) -> Response {
  case get_current_user(req, ctx) {
    Ok(user) -> next(user)
    Error(_) -> wisp.redirect(\"/login\")
  }
}
"
}

pub fn auth_test(app: String) -> String {
  "import gleeunit/should
import " <> app <> "/domain/auth

pub fn hash_password_test() {
  let hash = auth.hash_password(\"secret123\")
  auth.verify_password(\"secret123\", hash)
  |> should.be_true
}

pub fn wrong_password_test() {
  let hash = auth.hash_password(\"secret123\")
  auth.verify_password(\"wrong\", hash)
  |> should.be_false
}
"
}
