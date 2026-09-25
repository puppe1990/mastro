//// Amarra Stream: named operations applied to the DOM.
////
//// Responses use `Content-Type: text/vnd.amarra-stream` and carry one
//// JSON op per line. The client applies them instead of morphing the
//// whole `#amarra-main`.

import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import wisp

pub const content_type = "text/vnd.amarra-stream"

pub const append_kind = "append"

pub const prepend_kind = "prepend"

pub const replace_kind = "replace"

pub const morph_kind = "morph"

pub const remove_kind = "remove"

pub const toast_kind = "toast"

pub type Op {
  Op(kind: String, target: String, html: String)
}

pub fn append(target: String, html: String) -> Op {
  Op(kind: append_kind, target: target, html: html)
}

pub fn prepend(target: String, html: String) -> Op {
  Op(kind: prepend_kind, target: target, html: html)
}

pub fn replace(target: String, html: String) -> Op {
  Op(kind: replace_kind, target: target, html: html)
}

pub fn morph(target: String, html: String) -> Op {
  Op(kind: morph_kind, target: target, html: html)
}

pub fn remove(target: String) -> Op {
  Op(kind: remove_kind, target: target, html: "")
}

pub fn toast(html: String) -> Op {
  Op(kind: toast_kind, target: "amarra-toast-host", html: html)
}

pub fn encode(op: Op) -> String {
  json.object([
    #("kind", json.string(op.kind)),
    #("target", json.string(op.target)),
    #("html", json.string(op.html)),
  ])
  |> json.to_string
}

pub fn encode_ops(ops: List(Op)) -> String {
  ops |> list.map(encode) |> string.join("\n")
}

/// One-shot response applying the given ops. For long-lived streams use
/// the server's chunked/SSE transport and flush after each `encode`.
pub fn write_http(ops: List(Op)) -> wisp.Response {
  wisp.response(200)
  |> response.set_header("content-type", content_type)
  |> wisp.string_body(encode_ops(ops))
}
