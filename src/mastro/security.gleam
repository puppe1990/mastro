//// Security headers, the production gate and client address resolution.
////
//// `headers` wraps the response written by the handler, so it runs right
//// after the crash recovery middleware and every response — static files
//// included — leaves with the same hardening.
////
//// `validate` is the boot gate: production refuses to start without the
//// values an app cannot invent at runtime.
////
//// `client_ip` trusts `X-Forwarded-For` only for peers the operator listed,
//// so a spoofed header from the open internet is ignored.

import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import wisp.{type Request, type Response}

/// `X-Content-Type-Options`: never let the browser guess a type.
pub const content_type_options = "nosniff"

/// `X-Frame-Options`: do not let another origin frame the app.
pub const frame_options = "SAMEORIGIN"

/// `Referrer-Policy`: send the origin to other sites, the path only to us.
pub const referrer_policy = "strict-origin-when-cross-origin"

/// `Permissions-Policy`: features the framework does not use.
pub const permissions_policy = "camera=(), geolocation=(), microphone=()"

/// Two years of HSTS, subdomains included.
pub const hsts = "max-age=63072000; includeSubDomains"

/// The default policy. Inline script is required by the theme FOUC snippet
/// and the Drive boot; escaping stays the primary defence. Roadmap: a per
/// request nonce or SRI hashes.
pub const default_csp = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; form-action 'self'; base-uri 'self'; frame-ancestors 'self'"

pub type Options {
  Options(production: Bool, csp: String)
}

/// The defaults: `production` turns HSTS on, `csp` is `default_csp`.
pub fn defaults(production: Bool) -> Options {
  Options(production: production, csp: default_csp)
}

/// Replace the policy, keeping the rest.
pub fn with_csp(options: Options, csp: String) -> Options {
  Options(..options, csp: csp)
}

/// Set the security headers on the response. A header the handler already
/// set is left alone, so a route can override a default deliberately.
pub fn headers(options: Options, next: fn() -> Response) -> Response {
  let hardening = case options.production {
    True -> [#("strict-transport-security", hsts), ..base()]
    False -> base()
  }

  [csp_header(options.csp), ..hardening]
  |> list.fold(next(), set_if_absent)
}

fn base() -> List(#(String, String)) {
  [
    #("x-content-type-options", content_type_options),
    #("x-frame-options", frame_options),
    #("referrer-policy", referrer_policy),
    #("permissions-policy", permissions_policy),
  ]
}

fn csp_header(csp: String) -> #(String, String) {
  #("content-security-policy", csp)
}

fn set_if_absent(resp: Response, header: #(String, String)) -> Response {
  case response.get_header(resp, header.0) {
    Ok(_) -> resp
    Error(_) -> response.set_header(resp, header.0, header.1)
  }
}

// -- Production gate ----------------------------------------------------------

pub type Error {
  /// `APP_URL` is required in production: absolute URLs cannot be guessed.
  MissingAppUrl
  /// A bearer `AdminAuth` route needs `ADMIN_TOKEN` set.
  MissingAdminToken
}

/// Refuse to boot a production app that is missing a value it cannot
/// invent: the external URL, and the admin token when admin routes exist.
pub fn validate(
  production production: Bool,
  app_url app_url: Option(String),
  admin_token admin_token: Option(String),
  admin_routes admin_routes: Bool,
) -> Result(Nil, List(Error)) {
  case production {
    False -> Ok(Nil)
    True -> {
      let errors = case present(app_url) {
        True -> []
        False -> [MissingAppUrl]
      }

      let errors = case admin_routes, present(admin_token) {
        True, False -> [MissingAdminToken, ..errors]
        _, _ -> errors
      }

      case errors {
        [] -> Ok(Nil)
        _ -> Error(list.reverse(errors))
      }
    }
  }
}

fn present(value: Option(String)) -> Bool {
  case value {
    Some(v) if v != "" -> True
    _ -> False
  }
}

/// A message for the operator: one line per missing value.
pub fn describe(errors: List(Error)) -> String {
  errors
  |> list.map(fn(error) {
    case error {
      MissingAppUrl -> "APP_URL is required when APP_ENV=prod"
      MissingAdminToken -> "ADMIN_TOKEN is required for admin routes"
    }
  })
  |> string.join("; ")
}

// -- Client address -----------------------------------------------------------

/// The address to attribute a request to.
///
/// `X-Forwarded-For` is only read when the peer is a trusted proxy, or when
/// `trusted_proxies` contains `"*"` (a platform that always sits behind its
/// own edge). Otherwise the peer address is the client.
pub fn client_ip(
  req: request.Request(a),
  peer_ip: Option(String),
  trusted_proxies: List(String),
) -> String {
  case trusted(peer_ip, trusted_proxies) {
    True ->
      forwarded(req)
      |> result.unwrap(known(peer_ip))
    False -> known(peer_ip)
  }
}

fn trusted(peer_ip: Option(String), trusted_proxies: List(String)) -> Bool {
  list.contains(trusted_proxies, "*")
  || case peer_ip {
    Some(peer) -> list.contains(trusted_proxies, peer)
    None -> False
  }
}

fn known(peer_ip: Option(String)) -> String {
  case peer_ip {
    Some(peer) if peer != "" -> peer
    _ -> "unknown"
  }
}

fn forwarded(req: request.Request(a)) -> Result(String, Nil) {
  use value <- result.try(forwarded_header(req))
  // The client is the leftmost hop; the rest were added by proxies.
  case string.split(value, ",") {
    [client, ..] ->
      case string.trim(client) {
        "" -> Error(Nil)
        ip -> Ok(ip)
      }
    [] -> Error(Nil)
  }
}

fn forwarded_header(req: request.Request(a)) -> Result(String, Nil) {
  case request.get_header(req, "x-forwarded-for") {
    Ok(value) if value != "" -> Ok(value)
    _ ->
      case request.get_header(req, "x-real-ip") {
        Ok(value) if value != "" -> Ok(value)
        _ -> Error(Nil)
      }
  }
}
