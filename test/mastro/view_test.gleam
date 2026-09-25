import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element
import lustre/element/html
import mastro/kit
import mastro/view

fn el(label: String) -> element.Element(Nil) {
  html.span([], [element.text(label)])
}

fn layout_app(inner: element.Element(Nil), title: String) -> String {
  html.div([], [html.h1([], [element.text(title)]), inner])
  |> element.to_string
}

fn layout_landing(inner: element.Element(Nil), _title: String) -> String {
  html.section([], [inner]) |> element.to_string
}

// 1. Named layouts are selectable by name.
pub fn named_layout_test() {
  let reg =
    view.empty()
    |> view.with_layout("app", layout_app)
    |> view.with_layout("landing", layout_landing)

  let assert Ok(app) = view.render(reg, "app", "Home", el("HOME"))
  should.be_true(string.contains(app, "HOME"))
  should.be_true(string.contains(app, "Home"))

  let assert Ok(landing) = view.render(reg, "landing", "Home", el("LAND"))
  should.be_true(string.contains(landing, "LAND"))
}

// 2. Pages can be nested one level, addressed as "blog/post".
pub fn nested_page_test() {
  let reg =
    view.empty()
    |> view.with_page("blog/post", fn() { el("POST") })
    |> view.with_page("home", fn() { el("HOME") })

  let assert Ok(page) = view.page(reg, "blog/post")
  should.be_true(string.contains(element.to_string(page()), "POST"))

  should.equal(view.page(reg, "blog"), Error(view.UnknownPage("blog")))
}

// 3. Components live at a flat stem and resolve.
pub fn flat_component_test() {
  let reg = view.empty() |> view.with_components(kit.defaults())

  let assert Ok(card) = view.component(reg, "card")
  let html = card([#("title", "Hello")], el("BODY")) |> element.to_string
  should.be_true(string.contains(html, "BODY"))
}

// 4. An app override wins over the shipped kit for the same stem.
pub fn component_override_test() {
  let reg =
    view.empty()
    |> view.with_components(kit.defaults())
    |> view.with_component("input", fn(_attrs, _inner) {
      el("OVERRIDDEN-INPUT")
    })

  let assert Ok(input) = view.component(reg, "input")
  let html = input([#("name", "title")], el("")) |> element.to_string
  should.be_true(string.contains(html, "OVERRIDDEN-INPUT"))
}

// 5. Unknown layout/page/component are errors, not crashes.
pub fn unknown_resolution_test() {
  let reg = view.empty()

  should.equal(view.layout(reg, "nope"), Error(view.UnknownLayout("nope")))
  should.equal(view.page(reg, "nope"), Error(view.UnknownPage("nope")))
  should.equal(
    view.component(reg, "nope"),
    Error(view.UnknownComponent("nope")),
  )
}

// 6. Boot validation rejects non-flat component stems (partials are flat only).
pub fn validate_rejects_nested_component_test() {
  let reg =
    view.empty()
    |> view.with_components(kit.defaults())
    |> view.with_component("posts/card", fn(_a, _i) { el("X") })

  let assert Error(errors) = view.validate(reg)
  should.equal(errors, [view.NonFlatComponent("posts/card")])
}

// 7. A registry with only flat, shipped components validates.
pub fn validate_ok_test() {
  let reg = view.empty() |> view.with_components(kit.defaults())
  should.equal(view.validate(reg), Ok(Nil))
}
