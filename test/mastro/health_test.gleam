import gleam/http/response
import gleam/string
import gleeunit/should
import mastro/health

pub fn json_reports_status_and_lan_urls_test() {
  let body = health.json(4000)

  body |> string.contains("\"status\":\"ok\"") |> should.be_true
  body |> string.contains("\"lan_urls\"") |> should.be_true
}

pub fn respond_is_json_with_200_test() {
  let resp = health.respond(4000)

  resp.status |> should.equal(200)
  response.get_header(resp, "content-type")
  |> should.equal(Ok("application/json; charset=utf-8"))
}
