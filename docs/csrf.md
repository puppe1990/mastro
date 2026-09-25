# CSRF Protection

Every state-changing request must echo a token issued in a cookie. Mastro
uses the double-submit pattern: there is no server-side store, the token
lives in the `cais_csrf` cookie and must come back in the request.

| Where | Name |
|-------|------|
| Cookie | `cais_csrf` |
| Form field | `csrf_token` |
| Header | `X-CSRF-Token` |
| Meta tag | `<meta name="csrf-token">` |

The cookie is `HttpOnly`, `SameSite=Lax` and `Secure` when the request is
HTTPS, so scripts read the token from the meta tag instead of the cookie.

## How it fits together

`csrf.issue` runs in the router middleware. It mints one token per request,
threads it, and sets the cookie when the visitor arrives without one:

```gleam
fn middleware(
  req: Request,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- dev_error.rescue(req)
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  use threaded_req <- csrf.issue(req)
  next(threaded_req)
}
```

Because the token is threaded, the meta tag, the hidden field and the
cookie always carry the same value — no second call can mint a different
one mid-request.

## Rendering the token

The generated layout renders the meta tag, which is what `amarra.js` reads
before sending a Drive request:

```gleam
pub fn wrap(inner: Element(Nil), page_title: String, req: Request) -> String {
  html([], [
    head([], [
      meta([charset("utf-8")]),
      csrf.meta_tag(csrf.token(req)),
      title([], page_title),
    ]),
    body([], [main([class("container")], [inner])]),
  ])
  |> element.to_document_string
}
```

Forms render the hidden field:

```gleam
form([action("/posts"), method("post")], [
  csrf.hidden_field(csrf.token(req)),
  // ...
])
```

The shipped kit injects the field for you when the form is given the
token — pass it once, never both ways:

```gleam
kit.form([#("action", "/posts"), #("csrf_token", csrf.token(req))], inner)
```

## Guarding handlers

Handlers that already parsed the form pass it along:

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))
  // ...
}
```

Handlers that have no use for the body — deletes, JSON endpoints — let
`require_request` parse a form body when there is one:

```gleam
pub fn delete(req: Request, ctx: Context, id: String) -> Response {
  use <- csrf.require_request(req)
  // ...
}
```

A request that does not match the cookie gets `403 Forbidden` and the
handler never runs. `GET`, `HEAD`, `OPTIONS` and `TRACE` pass without a
token; everything else requires one.

## JavaScript clients

Drive requests read the meta tag and send the header:

```js
import { CSRF_HEADER, csrfToken } from "/static/js/amarra.js";

await fetch("/posts", {
  method: "POST",
  headers: { [CSRF_HEADER]: csrfToken() },
  body: formData,
});
```

A client that never did a `GET` has no cookie and is rejected until it
does one — that round trip is what proves the token came from your origin.

## Testing

`wisp/simulate` carries cookies between a response and the next request:

```gleam
let get_response = csrf.issue(get_request, handler)
let token = simulate.read_body(get_response)

let post_request =
  simulate.browser_request(http.Post, "/posts")
  |> simulate.session(get_request, get_response)
  |> simulate.form_body([#(csrf.field_name, token)])
```
