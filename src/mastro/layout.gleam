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

pub const theme_key = "amarra-theme"

/// Inlined before CSS so a stored light theme does not flash dark.
const fouc_script = "try{if(localStorage.getItem(\"amarra-theme\")===\"light\"){document.documentElement.classList.add(\"light\")}}catch(e){}"

pub fn app(inner: Element(Nil), title: String) -> String {
  html.html([], [
    html.head([], [html.title([], title), html.script([], fouc_script)]),
    html.body([], [
      html.nav([attribute.id(nav_id)], []),
      html.main([attribute.id(main_id)], [inner]),
      html.div([attribute.id(toast_host_id)], []),
    ]),
  ])
  |> element.to_document_string
}
