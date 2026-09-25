//// Lustre-native view layer.
////
//// The Amarra contract is reinterpreted here as a registry of Gleam
//// components and layouts instead of runtime HTML templates (see
//// docs/adr/0001-view-layer.md).
////
//// - layouts are named and selected at runtime
//// - pages may be nested one level (`blog/post`)
//// - components live at a flat stem and are overridable by the app
//// - `validate` catches non-flat stems at boot, not on the first request

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import lustre/element.{type Element}

/// A named layout wraps page content and a title into a full HTML string.
pub type Layout =
  fn(Element(Nil), String) -> String

/// A component receives its attributes and its inner slot.
pub type Component =
  fn(List(#(String, String)), Element(Nil)) -> Element(Nil)

/// A page is a thunk so the registry can hold many views without data.
pub type Page =
  fn() -> Element(Nil)

pub type Registry {
  Registry(
    layouts: Dict(String, Layout),
    pages: Dict(String, Page),
    components: Dict(String, Component),
  )
}

pub type ViewError {
  UnknownLayout(String)
  UnknownPage(String)
  UnknownComponent(String)
  NonFlatComponent(String)
}

pub fn empty() -> Registry {
  Registry(layouts: dict.new(), pages: dict.new(), components: dict.new())
}

pub fn with_layout(reg: Registry, name: String, layout: Layout) -> Registry {
  Registry(..reg, layouts: dict.insert(reg.layouts, name, layout))
}

pub fn with_page(reg: Registry, name: String, page: Page) -> Registry {
  Registry(..reg, pages: dict.insert(reg.pages, name, page))
}

/// Register a component under its flat stem. An app registration with the
/// same stem overrides the shipped kit.
pub fn with_component(
  reg: Registry,
  stem: String,
  component: Component,
) -> Registry {
  Registry(..reg, components: dict.insert(reg.components, stem, component))
}

/// Bulk-register components; entries here override existing stems.
pub fn with_components(
  reg: Registry,
  components: Dict(String, Component),
) -> Registry {
  Registry(..reg, components: dict.merge(reg.components, components))
}

pub fn layout(reg: Registry, name: String) -> Result(Layout, ViewError) {
  dict.get(reg.layouts, name)
  |> result.map_error(fn(_) { UnknownLayout(name) })
}

pub fn page(reg: Registry, name: String) -> Result(Page, ViewError) {
  dict.get(reg.pages, name)
  |> result.map_error(fn(_) { UnknownPage(name) })
}

pub fn component(reg: Registry, stem: String) -> Result(Component, ViewError) {
  case string.contains(stem, "/") {
    // Partials are flat only, mirroring the Amarra loader contract.
    True -> Error(UnknownComponent(stem))
    False ->
      dict.get(reg.components, stem)
      |> result.map_error(fn(_) { UnknownComponent(stem) })
  }
}

/// Render page content through a named layout.
pub fn render(
  reg: Registry,
  layout_name: String,
  title: String,
  content: Element(Nil),
) -> Result(String, ViewError) {
  layout(reg, layout_name)
  |> result.map(fn(wrap) { wrap(content, title) })
}

/// Boot-time validation. Returns every non-flat component stem so the app
/// can fail fast instead of erroring on the first request.
pub fn validate(reg: Registry) -> Result(Nil, List(ViewError)) {
  let errors =
    reg.components
    |> dict.keys
    |> list.filter(fn(stem) { string.contains(stem, "/") })
    |> list.map(NonFlatComponent)

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}
