import gleam/http
import gleam/http/response
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import lustre/element
import mastro/csrf
import wisp
import wisp/simulate

// -- Helpers ------------------------------------------------------------------

/// A `GET` that renders its token, standing in for a page with the meta tag.
fn landing() -> #(wisp.Request, wisp.Response, String) {
  let request = simulate.browser_request(http.Get, "/posts")
  let resp =
    csrf.issue(request, fn(req) { wisp.html_response(csrf.token(req), 200) })
  #(request, resp, simulate.read_body(resp))
}

fn must_not_run() -> wisp.Response {
  panic as "the handler must not run for a rejected request"
}

fn sets_the_csrf_cookie(resp: wisp.Response) -> Bool {
  response.get_cookies(resp)
  |> list.any(fn(cookie) { cookie.0 == csrf.cookie_name })
}

// -- Double submit ------------------------------------------------------------

pub fn post_without_a_token_is_forbidden_test() {
  let req = simulate.browser_request(http.Post, "/posts")
  let resp = csrf.require(req, option.None, must_not_run)
  should.equal(resp.status, 403)
}

pub fn get_without_a_token_passes_and_sets_the_cookie_test() {
  let request = simulate.browser_request(http.Get, "/posts")
  let resp = csrf.issue(request, fn(_) { wisp.ok() })
  should.equal(resp.status, 200)
  should.be_true(sets_the_csrf_cookie(resp))
}

pub fn post_echoing_the_cookie_in_the_field_is_accepted_test() {
  let #(get_request, get_response, token) = landing()

  let request =
    simulate.browser_request(http.Post, "/posts")
    |> simulate.session(get_request, get_response)
    |> simulate.form_body([#("title", "Hello"), #(csrf.field_name, token)])

  let resp =
    wisp.require_form(request, fn(form) {
      csrf.require(request, option.Some(form), fn() {
        wisp.redirect("/posts/1")
      })
    })

  should.equal(resp.status, 303)
}

pub fn post_with_a_mismatched_field_is_forbidden_test() {
  let #(get_request, get_response, _token) = landing()

  let request =
    simulate.browser_request(http.Post, "/posts")
    |> simulate.session(get_request, get_response)
    |> simulate.form_body([#(csrf.field_name, csrf.generate())])

  let resp =
    wisp.require_form(request, fn(form) {
      csrf.require(request, option.Some(form), must_not_run)
    })

  should.equal(resp.status, 403)
}

pub fn post_echoing_the_cookie_in_the_header_is_accepted_test() {
  let #(get_request, get_response, token) = landing()

  let request =
    simulate.browser_request(http.Put, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.header(csrf.header_name, token)

  should.equal(csrf.validate(request, option.None), Ok(Nil))
}

pub fn stale_token_from_another_cookie_is_invalid_test() {
  let #(get_request, get_response, _token) = landing()

  let request =
    simulate.browser_request(http.Post, "/posts")
    |> simulate.session(get_request, get_response)
    |> simulate.form_body([#(csrf.field_name, csrf.generate())])

  should.equal(csrf.validate(request, option.None), Error(csrf.InvalidToken))
}

pub fn drive_request_without_the_header_is_forbidden_test() {
  let #(get_request, get_response, _token) = landing()

  let request =
    simulate.browser_request(http.Put, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.header("amarra-drive", "true")

  let resp = csrf.require(request, option.None, must_not_run)
  should.equal(resp.status, 403)
}

pub fn drive_request_with_the_header_passes_test() {
  let #(get_request, get_response, token) = landing()

  let request =
    simulate.browser_request(http.Put, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.header("amarra-drive", "true")
    |> simulate.header(csrf.header_name, token)

  let resp = csrf.require(request, option.None, fn() { wisp.ok() })
  should.equal(resp.status, 200)
}

// -- Middleware ---------------------------------------------------------------

pub fn require_request_accepts_a_form_post_with_the_field_test() {
  let #(get_request, get_response, token) = landing()

  let request =
    simulate.browser_request(http.Delete, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.form_body([#(csrf.field_name, token)])

  let resp = csrf.require_request(request, fn() { wisp.redirect("/posts") })
  should.equal(resp.status, 303)
}

pub fn require_request_accepts_a_header_only_request_test() {
  let #(get_request, get_response, token) = landing()

  let request =
    simulate.browser_request(http.Delete, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.header(csrf.header_name, token)

  let resp = csrf.require_request(request, fn() { wisp.redirect("/posts") })
  should.equal(resp.status, 303)
}

pub fn require_request_rejects_a_form_post_without_the_field_test() {
  let #(get_request, get_response, _token) = landing()

  let request =
    simulate.browser_request(http.Delete, "/posts/1")
    |> simulate.session(get_request, get_response)
    |> simulate.form_body([#("title", "No token here")])

  let resp = csrf.require_request(request, must_not_run)
  should.equal(resp.status, 403)
}

pub fn issue_threads_one_token_per_request_test() {
  let get_request = simulate.browser_request(http.Get, "/")
  let get_response =
    csrf.issue(get_request, fn(req) {
      let first = csrf.token(req)
      let second = csrf.token(req)
      should.equal(first, second)
      wisp.html_response(first, 200)
    })

  let token = simulate.read_body(get_response)
  should.be_true(sets_the_csrf_cookie(get_response))

  let carried =
    simulate.cookie(get_request, csrf.cookie_name, token, wisp.PlainText)
  should.equal(csrf.cookie_token(carried), option.Some(token))
}

pub fn issue_keeps_an_existing_cookie_test() {
  let request =
    simulate.cookie(
      simulate.browser_request(http.Get, "/"),
      csrf.cookie_name,
      "keep-me",
      wisp.PlainText,
    )

  let get_response =
    csrf.issue(request, fn(req) {
      should.equal(csrf.token(req), "keep-me")
      wisp.ok()
    })

  should.be_false(sets_the_csrf_cookie(get_response))
}

pub fn safe_methods_never_require_a_token_test() {
  should.be_false(csrf.requires_token(http.Get))
  should.be_false(csrf.requires_token(http.Head))
  should.be_false(csrf.requires_token(http.Options))
  should.be_true(csrf.requires_token(http.Post))
  should.be_true(csrf.requires_token(http.Put))
  should.be_true(csrf.requires_token(http.Patch))
  should.be_true(csrf.requires_token(http.Delete))
}

pub fn generate_is_random_hex_test() {
  let one = csrf.generate()
  let two = csrf.generate()
  should.not_equal(one, two)
  should.equal(string.length(one), 64)
}

// -- Rendering ----------------------------------------------------------------

pub fn meta_tag_carries_the_token_test() {
  let html = csrf.meta_tag("abc123") |> element.to_string
  should.be_true(string.contains(html, "name=\"csrf-token\""))
  should.be_true(string.contains(html, "content=\"abc123\""))
}

pub fn hidden_field_carries_the_token_test() {
  let html = csrf.hidden_field("abc123") |> element.to_string
  should.be_true(string.contains(html, "type=\"hidden\""))
  should.be_true(string.contains(html, "name=\"csrf_token\""))
  should.be_true(string.contains(html, "value=\"abc123\""))
}
