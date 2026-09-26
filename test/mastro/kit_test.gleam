import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element
import lustre/element/html
import mastro/kit
import mastro/view

fn reg() -> view.Registry {
  view.empty() |> view.with_components(kit.defaults())
}

fn render(component: view.Component, attrs: List(#(String, String))) -> String {
  component(attrs, element.text("INNER")) |> element.to_string
}

pub fn defaults_stems_test() {
  let stems = kit.defaults() |> dict.keys |> list.sort(string.compare)
  should.equal(stems, [
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
  ])
  should.equal(stems, kit.required_stems)
}

pub fn input_error_test() {
  let assert Ok(input) = view.component(reg(), "input")
  let out = render(input, [#("name", "title"), #("error", "Required")])
  should.be_true(string.contains(out, "title"))
  should.be_true(string.contains(out, "Required"))
  should.be_true(string.contains(out, "field-error"))
}

pub fn input_ok_test() {
  let assert Ok(input) = view.component(reg(), "input")
  let out = render(input, [#("name", "title"), #("value", "Hello")])
  should.be_true(string.contains(out, "Hello"))
  should.be_false(string.contains(out, "field-error"))
}

pub fn flash_state_test() {
  let assert Ok(flash) = view.component(reg(), "flash")
  should.equal(render(flash, []) |> string.trim, "")
  should.be_true(string.contains(
    render(flash, [#("message", "Saved!")]),
    "Saved!",
  ))
}

pub fn form_test() {
  let assert Ok(form) = view.component(reg(), "form")
  let out = render(form, [#("action", "/items"), #("method", "post")])
  should.be_true(string.contains(out, "action=\"/items\""))
  should.be_true(string.contains(out, "method=\"post\""))
  should.be_true(string.contains(out, "INNER"))
}

pub fn form_injects_the_csrf_field_test() {
  let assert Ok(form) = view.component(reg(), "form")
  let out = render(form, [#("action", "/items"), #("csrf_token", "tok-123")])
  should.be_true(string.contains(out, "name=\"csrf_token\""))
  should.be_true(string.contains(out, "value=\"tok-123\""))
}

pub fn form_without_a_token_adds_no_field_test() {
  let assert Ok(form) = view.component(reg(), "form")
  let out = render(form, [#("action", "/items")])
  should.be_false(string.contains(out, "csrf_token"))
}

pub fn password_hook_test() {
  let assert Ok(password) = view.component(reg(), "password")
  let out = render(password, [#("name", "password")])
  should.be_true(string.contains(out, "type=\"password\""))
  should.be_true(string.contains(out, "data-amarra-hook=\"password\""))
}

pub fn nav_hook_test() {
  let assert Ok(nav) = view.component(reg(), "nav")
  let out = render(nav, [])
  should.be_true(string.contains(out, "<nav"))
  should.be_true(string.contains(out, "data-amarra-hook=\"nav\""))
}

pub fn select_test() {
  let out =
    kit.select(
      "category_id",
      [
        kit.SelectOption(value: "1", label: "A"),
        kit.SelectOption(value: "2", label: "B"),
      ],
      "2",
      "",
    )
    |> element.to_string
  should.be_true(string.contains(out, "value=\"1\""))
  should.be_true(string.contains(out, "selected"))
}

pub fn textarea_error_test() {
  let out = kit.textarea("body", "hello", "Too short") |> element.to_string
  should.be_true(string.contains(out, "hello"))
  should.be_true(string.contains(out, "Too short"))
}

pub fn checkbox_test() {
  let out = kit.checkbox("done", True, "Done") |> element.to_string
  should.be_true(string.contains(out, "checked"))
  should.be_true(string.contains(out, "Done"))
}

pub fn table_sort_test() {
  let out =
    kit.table(
      [
        kit.Column(field: "title", label: "Title", sortable: True),
        kit.Column(field: "id", label: "ID", sortable: False),
      ],
      [html.tr([], [html.td([], [element.text("Row")])])],
      "/posts",
      "title",
      "asc",
    )
    |> element.to_string
  should.be_true(string.contains(out, "Row"))
  should.be_true(string.contains(out, "aria-sort=\"ascending\""))
  should.be_true(string.contains(out, "?sort=title"))
  should.be_true(string.contains(out, "dir=desc"))
}

pub fn pagination_base_test() {
  let out = kit.pagination("/posts", 2, 5) |> element.to_string
  should.be_true(string.contains(out, "/posts?page=1"))
  should.be_true(string.contains(out, "/posts?page=5"))
  should.be_true(string.contains(out, "aria-current=\"page\""))
  should.be_true(string.contains(out, "aria-label=\"Pagination\""))
}

pub fn pagination_keeps_a_filter_in_the_link_test() {
  let out =
    kit.pagination("/posts?q=term&sort=title&dir=asc", 2, 5)
    |> element.to_string
  should.be_true(string.contains(
    out,
    "/posts?q=term&amp;sort=title&amp;dir=asc&amp;page=3",
  ))
}

pub fn table_keeps_a_filter_in_the_sort_link_test() {
  let out =
    kit.table(
      [kit.Column(field: "title", label: "Title", sortable: True)],
      [],
      "/posts?q=term",
      "title",
      "asc",
    )
    |> element.to_string
  should.be_true(string.contains(out, "/posts?q=term&amp;sort=title"))
  should.be_true(string.contains(out, "dir=desc"))
}

pub fn link_to_data_attrs_test() {
  let out =
    kit.link_to("/items/1", "Delete", [
      #("method", "delete"),
      #("confirm", "Sure?"),
    ])
    |> element.to_string
  should.be_true(string.contains(out, "href=\"/items/1\""))
  should.be_true(string.contains(out, "data-amarra-method=\"delete\""))
  should.be_true(string.contains(out, "data-amarra-confirm=\"Sure?\""))
}

pub fn filters_test() {
  let out = kit.filters("/posts", element.text("Q")) |> element.to_string
  should.be_true(string.contains(out, "action=\"/posts\""))
  should.be_true(string.contains(out, "method=\"get\""))
  should.be_true(string.contains(out, "Q"))
}

pub fn modal_test() {
  let assert Ok(modal) = view.component(reg(), "modal")
  let out = render(modal, [#("id", "confirm")])
  should.be_true(string.contains(out, "<dialog"))
  should.be_true(string.contains(out, "data-amarra-dialog-target=\"confirm\""))
}

pub fn stat_test() {
  let assert Ok(stat) = view.component(reg(), "stat")
  let out = render(stat, [#("label", "Requests"), #("value", "42")])
  should.be_true(string.contains(out, "Requests"))
  should.be_true(string.contains(out, "42"))
}

pub fn empty_state_test() {
  let assert Ok(empty) = view.component(reg(), "empty")
  let out = render(empty, [#("title", "No posts yet")])
  should.be_true(string.contains(out, "No posts yet"))
  should.be_true(string.contains(out, "INNER"))
}

pub fn locale_toggle_test() {
  let assert Ok(toggle) = view.component(reg(), "locale-toggle")
  let out = render(toggle, [#("href", "?locale=en"), #("label", "EN")])
  should.be_true(string.contains(out, "href=\"?locale=en\""))
  should.be_true(string.contains(out, "EN"))
}
