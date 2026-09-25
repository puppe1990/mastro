//// Drive and Frame request protocol.
////
//// Drive is a client concern: the server always returns the full layout
//// and `amarra.js` morphs `#amarra-main`. Frame requests (`Amarra-Frame:
//// <id>`) return only the fragment for that id.
////
//// Handlers call `write` and never branch on the transport headers.

import gleam/dict.{type Dict}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/element.{type Element}
import mastro/view.{type Layout}
import wisp

pub const drive_header = "amarra-drive"

pub const frame_header = "amarra-frame"

pub fn is_drive(req: Request(a)) -> Bool {
  case request.get_header(req, drive_header) {
    Ok(value) -> string.lowercase(value) == "true"
    Error(_) -> False
  }
}

pub fn frame_id(req: Request(a)) -> Option(String) {
  case request.get_header(req, frame_header) {
    Ok(value) ->
      case value {
        "" -> None
        _ -> Some(value)
      }
    Error(_) -> None
  }
}

/// Render the response for a request. A known frame id yields just that
/// fragment; anything else yields the full layout (Drive included).
pub fn write(
  req: Request(a),
  wrap: Layout,
  title: String,
  content: Element(Nil),
  frames: Dict(String, Element(Nil)),
) -> wisp.Response {
  case frame_id(req) {
    Some(id) ->
      case dict.get(frames, id) {
        Ok(fragment) -> wisp.html_response(element.to_string(fragment), 200)
        Error(_) -> wisp.html_response(wrap(content, title), 200)
      }
    None -> wisp.html_response(wrap(content, title), 200)
  }
}
