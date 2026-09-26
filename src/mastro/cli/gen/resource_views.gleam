/// The generated HTML views: admin index, public list, show and form.
///
import gleam/list
import gleam/string
import mastro/cli/gen/options
import mastro/cli/gen/resource_seed
import mastro/cli/gen/source

pub fn resource_views(
  app_name: String,
  resource_plural: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  references: List(String),
  sortable: List(String),
  display_field: String,
  options: options.ResourceOptions,
) -> String {
  let first_field = case fields {
    [#(name, _), ..] -> name
    [] -> "id"
  }
  let admin_base = "/admin/" <> resource_plural

  let form_field_elements =
    fields
    |> list.map(fn(f) {
      let #(fname, ftype) = f
      let label_text = source.field_label(fname)
      case ftype {
        "bool" -> "      div([class(\"field\")], [
        label([], [
          input([type_(\"checkbox\"), name(\"" <> fname <> "\"), attribute.checked(values." <> fname <> ")]),
          text(\" " <> label_text <> "\"),
        ]),
      ]),"
        "text" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        textarea([name(\"" <> fname <> "\")], values." <> fname <> "),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "int" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(int.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        "float" -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"number\"), name(\"" <> fname <> "\"), value(float.to_string(values." <> fname <> "))]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
        _ -> "      div([class(\"field\")], [
        label([], [text(\"" <> label_text <> "\")]),
        input([type_(\"text\"), name(\"" <> fname <> "\"), value(values." <> fname <> ")]),
        field_error(errors, \"" <> fname <> "\"),
      ]),"
      }
    })
    |> string.join("\n")

  let float_import = case list.any(fields, fn(f) { f.1 == "float" }) {
    True -> "\nimport gleam/float"
    False -> ""
  }
  let bool_import = case list.any(fields, fn(f) { f.1 == "bool" }) {
    True -> "\nimport gleam/bool"
    False -> ""
  }
  let html_imports = case list.any(fields, fn(f) { f.1 == "text" }) {
    True -> "a, button, div, form, h1, input, label, p, section, textarea,"
    False -> "a, button, div, form, h1, input, label, p, section,"
  }

  let columns =
    fields
    |> list.map(fn(f) {
      let #(fname, _) = f
      "    kit.Column(field: \""
      <> fname
      <> "\", label: \""
      <> source.field_label(fname)
      <> "\", sortable: "
      <> source.bool_literal(list.contains(sortable, fname))
      <> "),"
    })
    |> string.join("\n")

  let row_cells =
    fields
    |> list.index_map(fn(f, index) {
      let #(fname, ftype) = f
      let value = source.field_to_text(ftype, "item." <> fname)
      let content = case index {
        0 ->
          "a([href(\""
          <> admin_base
          <> "/\" <> int.to_string(item.id))], [text("
          <> value
          <> ")])"
        _ -> "text(" <> value <> ")"
      }
      "        html.td([], [" <> content <> "]),"
    })
    |> string.join("\n")

  // The public list is a label plus the numbers and flags of each row: the
  // long text fields stay out of a listing.
  let public_meta =
    fields
    |> list.filter(fn(f) {
      let #(fname, ftype) = f
      fname != display_field
      && !resource_seed.is_reference(fname, references)
      && { ftype == "int" || ftype == "float" || ftype == "bool" }
    })
    |> list.map(fn(f) {
      let #(fname, ftype) = f
      "            html.span([], [text(\""
      <> source.field_label(fname)
      <> ": \"), text("
      <> source.field_to_text(ftype, "item." <> fname)
      <> ")]),"
    })
    |> string.join("\n")

  let public_meta_block = case public_meta {
    "" -> ""
    _ -> "
            html.div([class(\"item-meta\")], [
" <> public_meta <> "
            ]),"
  }

  let display_text = case list.find(fields, fn(f) { f.0 == display_field }) {
    Ok(#(_, ftype)) -> source.field_to_text(ftype, "item." <> display_field)
    Error(_) -> "int.to_string(item.id)"
  }

  let public_view = case options.public {
    False -> ""
    True -> "
/// Public list: the search box and the page links, no admin links.
pub fn public_index_view(
  items: List(" <> type_name <> "),
  q: String,
  page: Int,
  pages: Int,
) -> Element(Nil) {
  section([class(\"" <> resource_plural <> "\")], [
    h1([], [text(\"" <> type_name <> "s\")]),
    kit.filters(\"/" <> resource_plural <> "\", input([name(\"q\"), value(q)])),
    case items {
      [] ->
        kit.empty_state([#(\"title\", \"No " <> type_name <> "s yet\")], text(\"\"))
      _ ->
        html.ul([class(\"" <> resource_singular <> "-list\")], list.map(items, fn(item) {
          html.li([], [
            html.p([class(\"item-title\")], [text(" <> display_text <> ")])," <> public_meta_block <> "
          ])
        }))
    },
    case pages > 1 {
      True ->
        kit.pagination(
          query.url(\"/" <> resource_plural <> "\", [#(\"q\", q)]),
          page,
          pages,
        )
      False -> text(\"\")
    },
  ])
}
"
  }

  "import gleam/int" <> float_import <> bool_import <> "
import gleam/list
import gleam/option
import lustre/attribute.{class, href, name, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{" <> html_imports <> "}
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import mastro/csrf
import mastro/kit
import mastro/query

/// Admin index: a search on " <> display_field <> ", a whitelisted sort and
/// one page of rows.
pub fn index_view(
  items: List(" <> type_name <> "),
  q: String,
  sort: String,
  dir: String,
  page: Int,
  pages: Int,
) -> Element(Nil) {
  let columns = [
" <> columns <> "
  ]
  let rows =
    list.map(items, fn(item) {
      html.tr([], [
" <> row_cells <> "
      ])
    })

  section([class(\"" <> resource_plural <> "\")], [
    div([class(\"header\")], [
      h1([], [text(\"" <> type_name <> "s\")]),
      a(
        [href(\"" <> admin_base <> "/new\"), class(\"btn\")],
        [text(\"New " <> type_name <> "\")],
      ),
    ]),
    kit.filters(\"" <> admin_base <> "\", html.div([class(\"filters-fields\")], [
      input([type_(\"hidden\"), name(\"sort\"), value(sort)]),
      input([type_(\"hidden\"), name(\"dir\"), value(dir)]),
      input([name(\"q\"), value(q)]),
    ])),
    case items {
      [] ->
        kit.empty_state(
          [#(\"title\", \"No " <> type_name <> "s yet\")],
          a([href(\"" <> admin_base <> "/new\")], [text(\"Create the first one\")]),
        )
      _ ->
        kit.table(
          columns,
          rows,
          query.url(\"" <> admin_base <> "\", [#(\"q\", q)]),
          sort,
          dir,
        )
    },
    case pages > 1 {
      True ->
        kit.pagination(
          query.url(\"" <> admin_base <> "\", [
            #(\"q\", q),
            #(\"sort\", sort),
            #(\"dir\", dir),
          ]),
          page,
          pages,
        )
      False -> text(\"\")
    },
  ])
}

pub fn show_view(item: " <> type_name <> ") -> Element(Nil) {
  section([class(\"" <> resource_singular <> "\")], [
    h1([], [text(item." <> first_field <> ")]),
    div([class(\"actions\")], [
      a(
        [
          href(\"" <> admin_base <> "/\" <> int.to_string(item.id) <> \"/edit\"),
          class(\"btn\"),
        ],
        [text(\"Edit\")],
      ),
    ]),
  ])
}

pub fn form_view(
  values: " <> resource_singular <> "_form." <> type_name <> "Form,
  errors: List(#(String, String)),
  csrf_token: String,
) -> Element(Nil) {
  let post_action = case values.id {
    option.Some(id) -> \"" <> admin_base <> "/\" <> int.to_string(id)
    option.None -> \"" <> admin_base <> "\"
  }

  section([class(\"" <> resource_singular <> "-form\")], [
    h1([], [text(case values.id {
      option.Some(_) -> \"Edit " <> type_name <> "\"
      option.None -> \"New " <> type_name <> "\"
    })]),
    form([attribute.action(post_action), attribute.method(\"post\")], [
      csrf.hidden_field(csrf_token),
      case values.id {
        option.Some(_) -> input([type_(\"hidden\"), name(\"_method\"), value(\"put\")])
        option.None -> text(\"\")
      },
" <> form_field_elements <> "
      button([type_(\"submit\"), class(\"btn\")], [text(\"Save\")]),
    ]),
  ])
}

fn field_error(
  errors: List(#(String, String)),
  field: String,
) -> Element(Nil) {
  case list.find(errors, fn(e) { e.0 == field }) {
    Ok(#(_, message)) -> p([class(\"error\")], [text(message)])
    Error(_) -> text(\"\")
  }
}
" <> public_view
}
