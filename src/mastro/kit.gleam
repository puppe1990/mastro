//// Shipped component kit.
////
//// Apps override any stem through `view.with_component`; the shipped
//// module is the default, not an untouchable base.

import gleam/dict.{type Dict}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import mastro/view.{type Component}

/// Stems the kit is expected to provide.
pub const required_stems = ["input", "button", "flash", "card"]

pub fn defaults() -> Dict(String, Component) {
  dict.from_list([
    #("input", input),
    #("button", button),
    #("flash", flash),
    #("card", card),
  ])
}

fn input(attrs: List(#(String, String)), _inner: Element(Nil)) -> Element(Nil) {
  html.input([
    attribute.type_("text"),
    attribute.name(attr_or(attrs, "name", "")),
    attribute.value(attr_or(attrs, "value", "")),
  ])
}

fn button(_attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.button([attribute.type_("submit")], [inner])
}

fn flash(attrs: List(#(String, String)), _inner: Element(Nil)) -> Element(Nil) {
  html.div([attribute.class("flash")], [
    html.span([], [element.text(attr_or(attrs, "message", ""))]),
  ])
}

fn card(attrs: List(#(String, String)), inner: Element(Nil)) -> Element(Nil) {
  html.section([attribute.class("card")], [
    html.h2([], [element.text(attr_or(attrs, "title", ""))]),
    inner,
  ])
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
