/// File templates for the generated web layer: router, handlers, layout.
///
import mastro/cli/types.{type DbChoice}

pub fn router_module(name: String, _db: DbChoice) -> String {
  "import gleam/http
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import " <> name <> "/web/error_handler
import " <> name <> "/web/health_handler
import " <> name <> "/web/home_handler
import mastro/csrf
import mastro/dev_error
import mastro/dev_log
import mastro/security
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- middleware(ctx, req)

  case wisp.path_segments(req), req.method {
    [], http.Get -> home_handler.index(req, ctx)
    [\"health\"], http.Get -> health_handler.index(req, ctx)
    [\"logs\"], http.Get ->
      dev_log.viewer(ctx.logs, config.is_development(ctx.config), req)
    _, _ -> error_handler.not_found(req)
  }
}

fn middleware(
  ctx: Context,
  req: Request,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- dev_log.request_log(ctx.logs, req)
  use <- dev_error.rescue(req)
  use <- security.headers(security.defaults(config.is_production(ctx.config)))
  use <- wisp.serve_static(req, under: \"/static\", from: priv_static())
  use threaded_req <- csrf.issue(req)
  next(threaded_req)
}

fn priv_static() -> String {
  let assert Ok(priv) = wisp.priv_directory(\"" <> name <> "\")
  priv <> \"/static\"
}
"
}

pub fn home_handler(name: String) -> String {
  "import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import " <> name <> "/config
import " <> name <> "/context.{type Context}
import " <> name <> "/web/layouts/root_layout
import wisp.{type Request, type Response}

pub fn index(req: Request, ctx: Context) -> Response {
  section([class(\"hero\")], [
    h1([], [text(config.t(ctx.config, \"app.welcome\") <> \" \" <> config.app_name)]),
    p([], [text(\"Built with Mastro — a convention-first web framework for Gleam.\")]),
  ])
  |> root_layout.wrap_site(
    config.t(ctx.config, \"app.home\"),
    req,
    config.site(ctx.config),
  )
  |> wisp.html_response(200)
}
"
}

pub fn error_handler(_name: String) -> String {
  "import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, p, section}
import wisp.{type Request, type Response}

pub fn not_found(_req: Request) -> Response {
  section([class(\"error-page\")], [
    h1([], [text(\"404\")]),
    p([], [text(\"Page not found.\")]),
  ])
  |> element.to_string
  |> wisp.html_response(404)
}

pub fn internal_error(_req: Request) -> Response {
  section([class(\"error-page\")], [
    h1([], [text(\"500\")]),
    p([], [text(\"Something went wrong.\")]),
  ])
  |> element.to_string
  |> wisp.html_response(500)
}
"
}

pub fn root_layout(name: String) -> String {
  "import lustre/attribute.{charset, class, content, href, id, name, rel, src}
import lustre/element.{type Element}
import lustre/element/html.{body, div, head, html, link, main, meta, nav, script, title}
import mastro/csrf
import mastro/meta
import wisp.{type Request}

/// Render a page deriving the site URL from the request. Prefer
/// `wrap_site` with `config.site(ctx.config)` so `APP_URL` is used.
pub fn wrap(inner: Element(Nil), page_title: String, req: Request) -> String {
  wrap_site(
    inner,
    page_title,
    req,
    meta.site(\"" <> name <> "\") |> meta.for_request(req),
  )
}

/// Render a page with explicit site metadata (OG/Twitter tags).
pub fn wrap_site(
  inner: Element(Nil),
  page_title: String,
  req: Request,
  site: meta.Site,
) -> String {
  html([], [
    head([], [
      meta([charset(\"utf-8\")]),
      meta([name(\"viewport\"), content(\"width=device-width, initial-scale=1\")]),
      csrf.meta_tag(csrf.token(req)),
      title([], page_title),
      link([rel(\"stylesheet\"), href(\"/static/css/app.css\")]),
      ..meta.head_elements(site),
    ]),
    body([], [
      nav([id(\"amarra-nav\")], []),
      main([id(\"amarra-main\"), class(\"container\")], [inner]),
      div([id(\"amarra-toast-host\")], []),
      script([src(\"/static/js/amarra.js\")], \"\"),
    ]),
  ])
  |> element.to_document_string
}
"
}

pub fn health_handler(name: String) -> String {
  "import " <> name <> "/context.{type Context}
import mastro/health
import wisp.{type Request, type Response}

/// `GET /health` — the LAN URLs a phone can use to reach this server.
pub fn index(_req: Request, ctx: Context) -> Response {
  health.respond(ctx.config.port)
}
"
}

pub fn flash_component() -> String {
  "import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, p}
import gleam/option.{type Option, None, Some}

pub fn render(message: Option(String)) -> Element(Nil) {
  case message {
    Some(msg) ->
      div([class(\"flash\")], [
        p([], [text(msg)]),
      ])
    None -> text(\"\")
  }
}
"
}
