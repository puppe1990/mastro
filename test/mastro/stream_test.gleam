import gleam/http/response
import gleam/list
import gleam/string
import gleeunit/should
import mastro/stream
import wisp

fn body_of(resp: wisp.Response) -> String {
  let assert response.Response(_, _, wisp.Text(body)) = resp
  body
}

pub fn content_type_test() {
  should.equal(stream.content_type, "text/vnd.amarra-stream")
}

pub fn encode_op_test() {
  let encoded =
    stream.encode(stream.Op(kind: "append", target: "list", html: "<li>x</li>"))
  should.be_true(string.contains(encoded, "\"kind\":\"append\""))
  should.be_true(string.contains(encoded, "\"target\":\"list\""))
  should.be_true(string.contains(encoded, "\"html\":\"<li>x</li>\""))
}

pub fn encode_escapes_html_test() {
  let encoded = stream.encode(stream.append("list", "a\"b"))
  should.be_true(string.contains(encoded, "\\\"b"))
}

pub fn encode_ops_is_line_delimited_test() {
  let body =
    stream.encode_ops([stream.append("a", "1"), stream.morph("b", "2")])
  should.equal(list.length(string.split(body, "\n")), 2)
}

pub fn toast_targets_host_test() {
  should.equal(stream.toast("<div>hi</div>").target, "amarra-toast-host")
}

pub fn write_http_sets_content_type_test() {
  let resp = stream.write_http([stream.toast("<div>hi</div>")])
  should.equal(
    response.get_header(resp, "content-type"),
    Ok(stream.content_type),
  )
  should.be_true(string.contains(body_of(resp), "toast"))
}
