//// Shipped component kit.
////
//// Apps override any stem through `view.with_component`; the shipped
//// module is the default, not an untouchable base.
////
//// Uniform components take `(attrs, inner)`; structured ones (`select`,
//// `textarea`, `checkbox`, `table`, `pagination`, `filters`) take typed
//// arguments because attributes cannot express their shape.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import mastro/csrf
import mastro/view.{type Component}

pub type Column {
  Column(field: String, label: String, sortable: Bool)
}

pub type SelectOption {
  SelectOption(value: String, label: String)
}

/// Stems the kit provides, in sorted order.
pub const required_stems = [
  "button",
  "card",
  "empty",
  "flash",
  "form",
  "input",
  "locale-toggle",
  "modal",
  "nav",
  "password",
  "stat",
]

pub fn defaults() -> Dict(String, Component) {
  dict.from_list([
    #("button", button),
    #("card", card),
    #("empty", empty_state),
    #("flash", flash),
    #("form", form),
    #("input", input),
    #("locale-toggle", locale_toggle),
    #("modal", modal),
    #("nav", nav),
    #("password", password),
    #("stat", stat),
  ])
}

// -- Uniform components -------------------------------------------------------

/// A `csrf_token` attribute adds the hidden field the double-submit check
/// reads; pass it once, never alongside a hand-written field.
fn form(attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.form(
    [
      attribute.method(attr_or(attrs, "method", "post")),
      attribute.action(attr_or(attrs, "action", "")),
      attribute.class(attr_or(attrs, "class", "form")),
    ],
    [csrf_field(attr_or(attrs, "csrf_token", "")), inner],
  )
}

fn csrf_field(token: String) -> Element(Nil) {
  case token {
    "" -> element.text("")
    _ -> csrf.hidden_field(token)
  }
}

fn input(attrs: List(#(String, String)), _inner: Element(Nil)) -> Element(Nil) {
  let control =
    html.input([
      attribute.type_(attr_or(attrs, "type", "text")),
      attribute.name(attr_or(attrs, "name", "")),
      attribute.value(attr_or(attrs, "value", "")),
      attribute.class("input"),
    ])
  with_error(control, attr_or(attrs, "error", ""))
}

fn password(
  attrs: List(#(String, String)),
  _inner: Element(Nil),
) -> Element(Nil) {
  html.div([attribute.class("password-field")], [
    html.input([
      attribute.type_("password"),
      attribute.name(attr_or(attrs, "name", "password")),
      attribute.id(attr_or(attrs, "id", "password")),
    ]),
    html.button(
      [
        attribute.type_("button"),
        attribute.data("amarra-hook", "password"),
        attribute.data(
          "amarra-password-for",
          attr_or(attrs, "for", "#password"),
        ),
      ],
      [element.text(attr_or(attrs, "label", "Show"))],
    ),
  ])
}

fn button(attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.button(
    [
      attribute.type_(attr_or(attrs, "type", "submit")),
      attribute.class(attr_or(attrs, "class", "button")),
    ],
    [inner],
  )
}

fn flash(attrs: List(#(String, String)), _inner: Element(Nil)) -> Element(Nil) {
  case attr_or(attrs, "message", "") {
    "" -> element.text("")
    message -> html.div([attribute.class("flash")], [element.text(message)])
  }
}

fn nav(_attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.nav([attribute.data("amarra-hook", "nav")], [inner])
}

fn modal(attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  let id = attr_or(attrs, "id", "modal")
  html.dialog(
    [
      attribute.id(id),
      attribute.data("amarra-dialog-target", id),
    ],
    [inner],
  )
}

fn locale_toggle(
  attrs: List(#(String, String)),
  _inner: Element(Nil),
) -> Element(Nil) {
  html.a(
    [
      attribute.href(attr_or(attrs, "href", "?locale=pt")),
      attribute.rel("alternate"),
    ],
    [element.text(attr_or(attrs, "label", "PT"))],
  )
}

fn stat(attrs: List(#(String, String)), _inner: Element(Nil)) -> Element(Nil) {
  html.div([attribute.class("stat")], [
    html.span([attribute.class("stat-label")], [
      element.text(attr_or(attrs, "label", "")),
    ]),
    html.strong([attribute.class("stat-value")], [
      element.text(attr_or(attrs, "value", "")),
    ]),
  ])
}

fn empty_state(
  attrs: List(#(String, String)),
  inner: Element(Nil),
) -> Element(Nil) {
  html.div([attribute.class("empty")], [
    html.p([attribute.class("empty-title")], [
      element.text(attr_or(attrs, "title", "")),
    ]),
    inner,
  ])
}

fn card(attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.section([attribute.class("card")], [
    html.h2([], [element.text(attr_or(attrs, "title", ""))]),
    inner,
  ])
}

// -- Structured components ----------------------------------------------------

pub fn select(
  name: String,
  options: List(SelectOption),
  value: String,
  error: String,
) -> Element(Nil) {
  let opts =
    list.map(options, fn(option) {
      html.option(
        [
          attribute.value(option.value),
          attribute.selected(option.value == value),
        ],
        option.label,
      )
    })
  with_error(html.select([attribute.name(name)], opts), error)
}

pub fn textarea(name: String, value: String, error: String) -> Element(Nil) {
  with_error(html.textarea([attribute.name(name)], value), error)
}

pub fn checkbox(name: String, checked: Bool, label: String) -> Element(Nil) {
  html.label([attribute.class("checkbox")], [
    html.input([
      attribute.type_("checkbox"),
      attribute.name(name),
      attribute.checked(checked),
    ]),
    element.text(label),
  ])
}

pub fn table(
  cols: List(Column),
  rows: List(Element(Nil)),
  base: String,
  sort: String,
  dir: String,
) -> Element(Nil) {
  let headers = list.map(cols, th_for(base, sort, dir))
  html.table([attribute.class("table")], [
    html.thead([], [html.tr([], headers)]),
    html.tbody([], rows),
  ])
}

fn th_for(base: String, sort: String, dir: String) -> fn(Column) -> Element(Nil) {
  fn(column: Column) -> Element(Nil) {
    case column.sortable {
      False -> html.th([], [element.text(column.label)])
      True -> {
        let active = column.field == sort
        let next_dir = case active, dir {
          True, "asc" -> "desc"
          _, _ -> "asc"
        }
        let aria = case active, dir {
          True, "asc" -> "ascending"
          True, _ -> "descending"
          False, _ -> "none"
        }
        html.th([attribute.aria_sort(aria)], [
          html.a(
            [
              attribute.href(
                base <> "?sort=" <> column.field <> "&dir=" <> next_dir,
              ),
            ],
            [element.text(column.label)],
          ),
        ])
      }
    }
  }
}

pub fn pagination(base: String, page: Int, total_pages: Int) -> Element(Nil) {
  let links =
    list.range(1, total_pages)
    |> list.map(fn(n) {
      case n == page {
        True ->
          html.span(
            [attribute.class("page current"), attribute.aria_current("page")],
            [
              element.text(int.to_string(n)),
            ],
          )
        False ->
          html.a([attribute.href(base <> "?page=" <> int.to_string(n))], [
            element.text(int.to_string(n)),
          ])
      }
    })
  html.nav(
    [attribute.class("pagination"), attribute.aria_label("Pagination")],
    links,
  )
}

pub fn filters(action: String, inner: Element(Nil)) -> Element(Nil) {
  html.form(
    [
      attribute.method("get"),
      attribute.action(action),
      attribute.class("filters"),
    ],
    [inner],
  )
}

/// A link that maps Drive options onto `data-amarra-*` attributes.
pub fn link_to(
  href: String,
  label: String,
  opts: List(#(String, String)),
) -> Element(Nil) {
  let attrs =
    list.map(opts, fn(option) {
      case option.0 {
        "method" -> attribute.data("amarra-method", option.1)
        "confirm" -> attribute.data("amarra-confirm", option.1)
        "frame" -> attribute.data("amarra-frame", option.1)
        "skip" -> attribute.data("amarra-skip", option.1)
        other -> attribute.attribute(other, option.1)
      }
    })
  html.a([attribute.href(href), ..attrs], [element.text(label)])
}

// -- Helpers ------------------------------------------------------------------

fn with_error(control: Element(Nil), error: String) -> Element(Nil) {
  case error {
    "" -> control
    _ ->
      html.div([attribute.class("field field-error")], [
        control,
        html.p([attribute.class("field-error-message")], [element.text(error)]),
      ])
  }
}

fn attr_or(
  attrs: List(#(String, String)),
  key: String,
  default: String,
) -> String {
  case list.key_find(attrs, key) {
    Ok(value) -> value
    Error(_) -> default
  }
}
