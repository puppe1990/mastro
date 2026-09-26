# Conventions

Naming, structure, and code patterns for generated code.

---

## File Naming

| Concept | File | Location |
|---------|------|----------|
| Handler | `post_handler.gleam` | `web/` |
| Views | `post_views.gleam` | `web/` |
| Form decoder | `post_form.gleam` | `web/forms/` |
| Domain type | `post.gleam` | `domain/` |
| Repo | `post_repo.gleam` | `data/` |
| Migration | `001_create_posts.sql` | `data/migrations/` |
| Layout | `root_layout.gleam` | `web/layouts/` |
| Component | `flash.gleam` | `web/components/` |
| Middleware | `auth.gleam` | `web/middleware/` |
| Test | `post_handler_test.gleam` | `test/<app>/web/` |

### Pluralization

- Resource names in CLI commands are **plural**: `mastro gen resource posts`
- Generated files use **singular**: `post_handler.gleam`, `post.gleam`
- Routes use **plural**: `/admin/posts`, `/admin/posts/:id`
- Types use **singular**: `Post`, `PostForm`, `PostParams`

---

## Handler Signatures

```gleam
// No params
pub fn index(req: Request, ctx: Context) -> Response

// With route param (always String from path segment)
pub fn show(req: Request, ctx: Context, id: String) -> Response
```

Handlers always take `Request` first, `Context` second, then route params.

Generated CRUD handlers open with the admin gate and the CSRF check:

```gleam
pub fn create(req: Request, ctx: Context) -> Response {
  use <- require_admin(req, ctx)
  use form_data <- wisp.require_form(req)
  use <- csrf.require(req, option.Some(form_data))
  // ...
}
```

---

## View Signatures

```gleam
// Admin index — search, whitelisted sort, one page of rows
pub fn index_view(
  items: List(Post),
  q: String,
  sort: String,
  dir: String,
  page: Int,
  pages: Int,
) -> Element(Nil)

// Public list (--public flag), read-only, no admin links
pub fn public_index_view(
  items: List(Post),
  q: String,
  page: Int,
  pages: Int,
) -> Element(Nil)

// Single item view
pub fn show_view(item: Post) -> Element(Nil)

// Form view (takes form state + errors)
pub fn form_view(values: PostForm, errors: List(#(String, String))) -> Element(Nil)
```

Views return `Element(Nil)`. They never import wisp or return Response.

Admin index views assemble their UI from `mastro/kit` (`kit.filters`, `kit.table`,
`kit.empty_state`, `kit.pagination`) and build URLs with `mastro/query`.

---

## Form Pattern

Every form has two types:

```gleam
// Display state — used to re-render the form with values
pub type PostForm {
  PostForm(id: Option(Int), title: String, body: String, published: Bool)
}

// Validated input — the clean data for domain/repo
pub type PostParams {
  PostParams(title: String, body: String, published: Bool)
}
```

And four functions:

```gleam
pub fn empty() -> PostForm                     // Blank form
pub fn from_post(post: Post) -> PostForm       // Edit form (named from_<singular>)
pub fn from_form_data(data: FormData) -> PostForm  // Re-render after error
pub fn decode(data: FormData) -> Result(PostParams, List(#(String, String)))
```

---

## Repo Signatures

Postgres repos take a `pog.Connection`; SQLite repos take the database path:

```gleam
// Postgres
pub fn list(db: pog.Connection) -> List(Post)
pub fn get(db: pog.Connection, id: Int) -> Result(Post, Nil)
pub fn create(db: pog.Connection, params: PostParams) -> Result(Post, Nil)
pub fn update(db: pog.Connection, id: Int, params: PostParams) -> Result(Post, Nil)
pub fn delete(db: pog.Connection, id: Int) -> Result(Nil, Nil)

// SQLite
pub fn list(db_path: String) -> List(Task)
pub fn get(db_path: String, id: Int) -> Result(Task, Nil)
```

The DB handle comes first, then params. Return domain types, never raw rows.

---

## Route Pattern

Routes live in `router.gleam` and follow RESTful conventions under `/admin`:

```gleam
case wisp.path_segments(req), req.method {
  ["admin", "posts"], http.Get -> post_handler.index(req, ctx)
  ["admin", "posts", "new"], http.Get -> post_handler.new(req, ctx)
  ["admin", "posts"], http.Post -> post_handler.create(req, ctx)
  ["admin", "posts", id], http.Get -> post_handler.show(req, ctx, id)
  ["admin", "posts", id, "edit"], http.Get -> post_handler.edit(req, ctx, id)
  ["admin", "posts", id], http.Put -> post_handler.update(req, ctx, id)
  ["admin", "posts", id], http.Delete -> post_handler.delete(req, ctx, id)
  _, _ -> error_handler.not_found(req)
}
```

`/new` comes before `/:id` to avoid ambiguity. `--public` adds a read-only
`["posts"], http.Get -> post_handler.public_index(req, ctx)`; `--api` serves the
same actions under `/api/`.

---

## Layout Pattern

```gleam
pub fn wrap(inner: Element(Nil), page_title: String, req: Request) -> String {
  html([], [
    head([], [ ... ]),
    body([], [ main([], [inner]) ]),
  ])
  |> element.to_document_string
}
```

Layouts are functions, not inheritance. A handler calls:

```gleam
post_views.index_view(posts, q, sort, dir, page, pages)
|> root_layout.wrap("Posts", req)
|> wisp.html_response(200)
```

---

## Flash Messages

Set on redirect:
```gleam
wisp.redirect("/posts")
|> mastro.set_flash(req, "info", "Post created")
```

Read in layout/component:
```gleam
let message = mastro.get_flash(req, "info")   // Result(String, Nil)
```

`set_flash` takes `(response, req, key, message)`; `get_flash` takes `(req, key)`
and returns a `Result` because the cookie may be absent.

---

## Field Types (CLI)

| CLI Type | Gleam Type | SQL Type (Postgres) | SQL Type (SQLite) |
|----------|-----------|--------------------|--------------------|
| `string` | `String` | `TEXT` | `TEXT` |
| `text` | `String` | `TEXT` | `TEXT` |
| `int` | `Int` | `INTEGER` | `INTEGER` |
| `float` | `Float` | `DOUBLE PRECISION` | `REAL` |
| `bool` | `Bool` | `BOOLEAN` | `INTEGER` |
| `date` | `String` | `DATE` | `TEXT` |
| `datetime` | `String` | `TIMESTAMPTZ` | `TEXT` |
| `optional(T)` | `Option(T)` | `T` (nullable) | `T` (nullable) |
| `posts:references` or `--belongs-to posts` | `post_id: Int` | FK to `posts.id` | FK to `posts.id` |
