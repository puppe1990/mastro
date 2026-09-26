# Routing

Mastro uses Gleam pattern matching for routing. All routes live in
one file: `src/<app>/router.gleam`.

## How it works

The router pattern matches on two things: the URL path segments and
the HTTP method.

```gleam
pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    ["posts"], http.Get -> post_handler.public_index(req, ctx)
    ["admin", "posts", id], http.Get -> post_handler.show(req, ctx, id)
    _, _ -> error_handler.not_found(req)
  }
}
```

`wisp.path_segments(req)` splits the URL path into a list of strings:
- `/` → `[]`
- `/posts` → `["posts"]`
- `/admin/posts/42` → `["admin", "posts", "42"]`
- `/admin/posts/42/edit` → `["admin", "posts", "42", "edit"]`

## Route parameters

Variables in the pattern become handler arguments:

```gleam
// /admin/posts/42 → id = "42"
["admin", "posts", id], http.Get -> post_handler.show(req, ctx, id)

// /admin/posts/42/edit → id = "42"
["admin", "posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
```

Route parameters are always strings. Parse them in the handler:

```gleam
pub fn show(req: Request, ctx: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> error_handler.not_found(req)
    Ok(id) -> // ... use the integer id
  }
}
```

## RESTful resource routes

`mastro gen resource posts ...` adds these admin routes:

```gleam
["admin", "posts"], http.Get -> post_handler.index(req, ctx)
["admin", "posts", "new"], http.Get -> post_handler.new(req, ctx)
["admin", "posts"], http.Post -> post_handler.create(req, ctx)
["admin", "posts", id], http.Get -> post_handler.show(req, ctx, id)
["admin", "posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
["admin", "posts", id], http.Put -> post_handler.update(req, ctx, id)
["admin", "posts", id], http.Delete -> post_handler.delete(req, ctx, id)
```

Note: `["admin", "posts", "new"]` comes before `["admin", "posts", id]`
so the literal `"new"` matches first and doesn't get captured as an id.

## The admin gate

Every admin action starts with the gate the resource was generated with
(`--admin-auth`, `session` by default):

```gleam
pub fn index(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  // ...
}
```

- `session` reads the signed `_user_id` cookie `mastro gen auth` writes
  and sends an anonymous visitor to `/login`. Swap in
  `auth.require_auth` when the handler needs the user row.
- `bearer` compares `ADMIN_TOKEN` with an `Authorization: Bearer`
  header (`mastro/security.bearer_authorized`). An unset token opens the
  gate in development; production refuses to boot without one, so the
  gate only closes there. `--admin-auth bearer` flips
  `admin_routes: True` in `config.validate/1` for you.

`--public` adds the list anyone can read, without the gate:

```gleam
["posts"], http.Get -> post_handler.public_index(req, ctx)
```

## The public list

`--public` renders `public_index_view`: `<.filters>` on the display
field, `<.empty>` when the search finds nothing and `<.pagination
base>` when there is more than one page. No admin links, no table
headers to sort by — the sort whitelist belongs to the admin index.

## Method override

HTML forms only support GET and POST. To send PUT and DELETE, Mastro
uses method override — a hidden form field `_method`:

```html
<form method="post" action="/admin/posts/42">
  <input type="hidden" name="_method" value="put">
  <!-- form fields -->
</form>
```

The middleware calls `wisp.method_override(req)` which reads `_method`
and changes the request method accordingly. This is already set up
in every generated project.

## Adding routes manually

Edit `router.gleam` and add a new pattern before the `_, _` catch-all:

```gleam
case wisp.path_segments(req), req.method {
  [], http.Get -> home_handler.index(req, ctx)
  ["dashboard"], http.Get -> dashboard_handler.index(req, ctx)  // new
  _, _ -> error_handler.not_found(req)
}
```

Don't forget to add the import at the top of the file.

## Middleware

Middleware runs before the route match. The default middleware stack:

```gleam
fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)     // PUT/DELETE via _method
  use <- wisp.log_request(req)            // log method + path
  use <- wisp.rescue_crashes              // catch panics, return 500
  use <- wisp.serve_static(req,           // serve priv/static/*
    under: "/static",
    from: priv_static(),
  )
  next(req)
}
```

Add custom middleware by inserting `use` calls:

```gleam
fn middleware(req: Request, next: fn(Request) -> Response) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: "/static", from: priv_static())
  use <- my_custom_middleware(req)          // your middleware
  next(req)
}
```

## Viewing all routes

```bash
mastro routes
```

Output:

```
GET     /                   home_handler.index
GET     /admin/posts        post_handler.index
GET     /admin/posts/new    post_handler.new
POST    /admin/posts        post_handler.create
GET     /admin/posts/:id    post_handler.show
GET     /admin/posts/:id/edit post_handler.edit
PUT     /admin/posts/:id    post_handler.update
DELETE  /admin/posts/:id    post_handler.delete
```

A resource generated with `--public` also lists the page anyone can
read:

```
GET     /posts              post_handler.public_index
```
