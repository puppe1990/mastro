//// Standard Amarra layout.
////
//// Drive morphs `#amarra-main` (and re-syncs `#amarra-nav`), so the ids
//// here are part of the public contract.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub const nav_id = "amarra-nav"

pub const main_id = "amarra-main"

pub const toast_host_id = "amarra-toast-host"

pub fn app(inner: Element(Nil), title: String) -> String {
  html.html([], [
    html.head([], [html.title([], title)]),
    html.body([], [
      html.nav([attribute.id(nav_id)], []),
      html.main([attribute.id(main_id)], [inner]),
      html.div([attribute.id(toast_host_id)], []),
    ]),
  ])
  |> element.to_document_string
}
