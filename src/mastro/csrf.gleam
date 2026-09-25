//// CSRF protection with the double-submit cookie pattern.
////
//// There is no server-side store: the token lives in the `cais_csrf`
//// cookie and must come back in the `csrf_token` form field or in the
//// `X-CSRF-Token` header. A request that does not echo the cookie is
//// rejected with `403`.
////
//// `issue` runs in the router middleware. It mints the token once per
//// request and threads it, so the layout meta tag, the form hidden field
//// and the cookie always carry the same value.
////
//// `require` guards every mutating handler, with the form body the
//// handler already parsed. Handlers that have no use for the body call
//// `require_request` instead.
////
//// ```gleam
//// fn middleware(req, next) {
////   use req <- csrf.issue(req)
////   next(req)
//// }
////
//// pub fn create(req, ctx) {
////   use form <- wisp.require_form(req)
////   use <- csrf.require(req, Some(form))
////   // ...
//// }
////
//// pub fn delete(req, ctx, id) {
////   use <- csrf.require_request(req)
////   // ...
//// }
//// ```

import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import wisp.{type Request, type Response}

/// The cookie that carries the double-submit token.
pub const cookie_name = "cais_csrf"

/// The form field a submitted token is read from.
pub const field_name = "csrf_token"

/// The header a submitted token is read from.
pub const header_name = "X-CSRF-Token"

/// The meta tag `amarra.js` reads the token from.
pub const meta_name = "csrf-token"

/// Where `issue` threads the minted token so the rest of the request sees
/// the same value without touching a store.
const threaded_header = "x-mastro-csrf-token"

/// The token outlives a single page render, so a stale tab can still post.
fn token_max_age() -> Int {
  60 * 60 * 24 * 7
}

pub type Error {
  /// The request carried no token cookie, so nothing could be matched.
  MissingToken
  /// A cookie was present but the submitted token did not match it.
  InvalidToken
}

/// Methods that change state, and so must carry a token.
pub fn requires_token(method: http.Method) -> Bool {
  case method {
    http.Get | http.Head | http.Options | http.Trace -> False
    _ -> True
  }
}

/// A fresh random token, hex encoded.
pub fn generate() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// The token from the request cookie, when there is one.
pub fn cookie_token(req: Request) -> Option(String) {
  case wisp.get_cookie(req, cookie_name, wisp.PlainText) {
    Ok(token) if token != "" -> Some(token)
    _ -> None
  }
}

/// The token this request is working with: the value `issue` threaded,
/// then the cookie, then a fresh one when neither is present.
pub fn token(req: Request) -> String {
  case request_header_token(req) {
    Some(token) -> token
    None ->
      case cookie_token(req) {
        Some(token) -> token
        None -> generate()
      }
  }
}

/// Mint the token for this request, thread it to the handler, and set the
/// cookie when the request arrived without one.
///
/// Safe methods always pass: the point of the round trip is that the `GET`
/// hands the client a token to echo back on the next `POST`.
pub fn issue(req: Request, next: fn(Request) -> Response) -> Response {
  let #(token, is_new) = case cookie_token(req) {
    Some(token) -> #(token, False)
    None -> #(generate(), True)
  }
  let req = request.set_header(req, threaded_header, token)
  let response = next(req)
  case is_new {
    True ->
      wisp.set_cookie(
        response,
        req,
        cookie_name,
        token,
        wisp.PlainText,
        token_max_age(),
      )
    False -> response
  }
}

/// Check a state-changing request against the double-submit cookie.
///
/// Safe methods pass without a token. Mutating requests must echo the
/// cookie in the `X-CSRF-Token` header or in the `csrf_token` field of the
/// form body that was already parsed.
pub fn validate(req: Request, form: Option(wisp.FormData)) -> Result(Nil, Error) {
  case requires_token(req.method) {
    False -> Ok(Nil)
    True ->
      case cookie_token(req) {
        None -> Error(MissingToken)
        Some(expected) ->
          case submitted(req, form) {
            Some(value) ->
              case matches(expected, value) {
                True -> Ok(Nil)
                False -> Error(InvalidToken)
              }
            None -> Error(InvalidToken)
          }
      }
  }
}

/// Guard a handler: a request that fails the double-submit check gets a
/// `403` and the handler never runs.
pub fn require(
  req: Request,
  form: Option(wisp.FormData),
  next: fn() -> Response,
) -> Response {
  case validate(req, form) {
    Ok(_) -> next()
    Error(_) -> forbidden()
  }
}

/// Guard a handler that has no use for the body: the token comes from the
/// header, or from the form when the request is a form post.
pub fn require_request(req: Request, next: fn() -> Response) -> Response {
  case is_form_post(req) {
    True -> wisp.require_form(req, fn(form) { require(req, Some(form), next) })
    False -> require(req, None, next)
  }
}

/// The `403` response an invalid request receives.
pub fn forbidden() -> Response {
  wisp.html_response("<h1>403 Forbidden</h1>", 403)
}

/// The `<meta name="csrf-token">` tag for the layout head. `amarra.js`
/// reads it and sends the token on Drive requests.
pub fn meta_tag(token: String) -> Element(Nil) {
  html.meta([attribute.name(meta_name), attribute.content(token)])
}

/// A hidden `csrf_token` field for a form that posts natively.
pub fn hidden_field(token: String) -> Element(Nil) {
  html.input([
    attribute.type_("hidden"),
    attribute.name(field_name),
    attribute.value(token),
  ])
}

// -- Internals ----------------------------------------------------------------

fn request_header_token(req: Request) -> Option(String) {
  case request.get_header(req, threaded_header) {
    Ok(token) if token != "" -> Some(token)
    _ -> None
  }
}

fn submitted(req: Request, form: Option(wisp.FormData)) -> Option(String) {
  case request.get_header(req, header_name) {
    Ok(value) if value != "" -> Some(value)
    _ ->
      case form {
        Some(data) ->
          case list.key_find(data.values, field_name) {
            Ok(value) if value != "" -> Some(value)
            _ -> None
          }
        None -> None
      }
  }
}

fn matches(expected: String, submitted: String) -> Bool {
  crypto.secure_compare(
    bit_array.from_string(expected),
    bit_array.from_string(submitted),
  )
}

fn is_form_post(req: Request) -> Bool {
  case request.get_header(req, "content-type") {
    Ok(content_type) ->
      string.starts_with(content_type, "application/x-www-form-urlencoded")
      || string.starts_with(content_type, "multipart/form-data")
    Error(_) -> False
  }
}
