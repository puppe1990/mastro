import gleam/http/request
import gleam/http/response
import gleam/option
import gleam/string
import gleeunit/should
import mastro/security
import wisp

fn header_of(resp: wisp.Response, name: String) -> Result(String, Nil) {
  response.get_header(resp, name)
}

fn ok_with(options: security.Options) -> wisp.Response {
  security.headers(options, fn() { wisp.ok() })
}

pub fn headers_are_set_on_every_response_test() {
  let resp = ok_with(security.defaults(False))
  should.equal(header_of(resp, "x-content-type-options"), Ok("nosniff"))
  should.equal(header_of(resp, "x-frame-options"), Ok(security.frame_options))
  should.equal(header_of(resp, "referrer-policy"), Ok(security.referrer_policy))
  should.equal(
    header_of(resp, "permissions-policy"),
    Ok(security.permissions_policy),
  )
  should.equal(
    header_of(resp, "content-security-policy"),
    Ok(security.default_csp),
  )
}

pub fn hsts_only_in_production_test() {
  let dev = ok_with(security.defaults(False))
  should.equal(header_of(dev, "strict-transport-security"), Error(Nil))

  let prod = ok_with(security.defaults(True))
  should.equal(header_of(prod, "strict-transport-security"), Ok(security.hsts))
}

pub fn csp_keeps_the_inline_script_the_fouc_snippet_needs_test() {
  should.be_true(string.contains(
    security.default_csp,
    "script-src 'self' 'unsafe-inline'",
  ))
}

pub fn a_handler_header_is_not_overwritten_test() {
  let resp =
    security.headers(security.defaults(False), fn() {
      wisp.ok() |> response.set_header("x-frame-options", "DENY")
    })

  should.equal(header_of(resp, "x-frame-options"), Ok("DENY"))
}

pub fn with_csp_replaces_the_policy_test() {
  let options =
    security.defaults(False)
    |> security.with_csp("default-src 'none'")

  should.equal(
    header_of(ok_with(options), "content-security-policy"),
    Ok("default-src 'none'"),
  )
}

// -- Production gate ----------------------------------------------------------

pub fn production_requires_app_url_test() {
  security.validate(
    production: True,
    app_url: option.None,
    admin_token: option.None,
    admin_routes: False,
  )
  |> should.equal(Error([security.MissingAppUrl]))
}

pub fn production_requires_admin_token_for_admin_routes_test() {
  security.validate(
    production: True,
    app_url: option.Some("https://app.test"),
    admin_token: option.None,
    admin_routes: True,
  )
  |> should.equal(Error([security.MissingAdminToken]))
}

pub fn production_without_admin_routes_needs_no_token_test() {
  security.validate(
    production: True,
    app_url: option.Some("https://app.test"),
    admin_token: option.None,
    admin_routes: False,
  )
  |> should.equal(Ok(Nil))
}

pub fn production_with_both_values_boots_test() {
  security.validate(
    production: True,
    app_url: option.Some("https://app.test"),
    admin_token: option.Some("token"),
    admin_routes: True,
  )
  |> should.equal(Ok(Nil))
}

pub fn dev_boots_without_any_value_test() {
  security.validate(
    production: False,
    app_url: option.None,
    admin_token: option.None,
    admin_routes: True,
  )
  |> should.equal(Ok(Nil))
}

pub fn describe_lists_every_missing_value_test() {
  security.describe([security.MissingAppUrl, security.MissingAdminToken])
  |> should.equal(
    "APP_URL is required when APP_ENV=prod; ADMIN_TOKEN is required for admin routes",
  )
}

// -- Client address -----------------------------------------------------------

pub fn untrusted_peer_is_the_client_test() {
  let req =
    request.new()
    |> request.set_header("x-forwarded-for", "203.0.113.7, 10.0.0.1")

  security.client_ip(req, option.Some("198.51.100.9"), [])
  |> should.equal("198.51.100.9")
}

pub fn trusted_peer_forwards_the_leftmost_hop_test() {
  let req =
    request.new()
    |> request.set_header("x-forwarded-for", "203.0.113.7, 10.0.0.1")

  security.client_ip(req, option.Some("10.0.0.1"), ["10.0.0.1"])
  |> should.equal("203.0.113.7")
}

pub fn wildcard_trusts_the_platform_edge_test() {
  let req =
    request.new() |> request.set_header("x-forwarded-for", "203.0.113.7")

  security.client_ip(req, option.None, ["*"])
  |> should.equal("203.0.113.7")
}

pub fn trusted_peer_without_the_header_stays_the_peer_test() {
  security.client_ip(request.new(), option.Some("10.0.0.1"), ["10.0.0.1"])
  |> should.equal("10.0.0.1")
}

pub fn unknown_peer_is_reported_as_unknown_test() {
  security.client_ip(request.new(), option.None, [])
  |> should.equal("unknown")
}

pub fn x_real_ip_is_the_fallback_test() {
  let req = request.new() |> request.set_header("x-real-ip", "203.0.113.7")

  security.client_ip(req, option.None, ["*"])
  |> should.equal("203.0.113.7")
}
