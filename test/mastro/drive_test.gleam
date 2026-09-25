import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/option
import gleam/string
import gleeunit/should
import lustre/element
import lustre/element/html
import mastro/drive
import mastro/layout
import mastro/view
import wisp

fn el(label: String) -> element.Element(Nil) {
  html.span([], [element.text(label)])
}

fn body_of(resp: wisp.Response) -> String {
  let assert response.Response(_, _, wisp.Text(body)) = resp
  body
}

pub fn is_drive_test() {
  let drive_req =
    request.new()
    |> request.set_header(drive.drive_header, "true")

  let plain_req = request.new()

  should.be_true(drive.is_drive(drive_req))
  should.be_false(drive.is_drive(plain_req))
}

pub fn frame_id_test() {
  let frame_req =
    request.new()
    |> request.set_header(drive.frame_header, "cart")

  should.equal(drive.frame_id(frame_req), option.Some("cart"))
  should.equal(drive.frame_id(request.new()), option.None)
}

pub fn drive_request_renders_full_page_test() {
  let drive_req =
    request.new()
    |> request.set_header(drive.drive_header, "true")

  let resp =
    drive.write(drive_req, layout.app, "Home", el("CONTENT"), dict.new())
  let body = body_of(resp)
  should.be_true(string.contains(body, "amarra-main"))
  should.be_true(string.contains(body, "CONTENT"))
}

pub fn plain_request_renders_full_page_test() {
  let resp =
    drive.write(request.new(), layout.app, "Home", el("CONTENT"), dict.new())
  should.be_true(string.contains(body_of(resp), "amarra-main"))
}

pub fn frame_request_renders_fragment_only_test() {
  let frame_req =
    request.new()
    |> request.set_header(drive.frame_header, "cart")

  let frames = dict.from_list([#("cart", el("CART"))])
  let resp = drive.write(frame_req, layout.app, "Home", el("CONTENT"), frames)
  let body = body_of(resp)
  should.be_true(string.contains(body, "CART"))
  should.be_false(string.contains(body, "amarra-main"))
  should.be_false(string.contains(body, "CONTENT"))
}

pub fn frame_unknown_falls_back_to_page_test() {
  let frame_req =
    request.new()
    |> request.set_header(drive.frame_header, "nope")

  let resp =
    drive.write(frame_req, layout.app, "Home", el("CONTENT"), dict.new())
  should.be_true(string.contains(body_of(resp), "amarra-main"))
}
