import gleam/http
import gleam/http/request
import gleam/option
import gleam/string
import gleeunit/should
import mastro/meta

pub fn image_is_absolute_when_the_site_has_a_url_test() {
  meta.site_from("app", option.Some("https://app.test"))
  |> meta.with_image("/static/og.png")
  |> meta.image_url
  |> should.equal(option.Some("https://app.test/static/og.png"))
}

pub fn image_stays_relative_without_a_url_test() {
  meta.site_from("app", option.None)
  |> meta.image_url
  |> should.equal(option.Some("/static/og.png"))
}

pub fn for_request_fills_the_url_from_the_host_test() {
  let req =
    request.new()
    |> request.set_scheme(http.Http)
    |> request.set_header("host", "localhost:4000")

  let site = meta.site_from("app", option.None) |> meta.for_request(req)

  site.url |> should.equal(option.Some("http://localhost:4000"))
}

pub fn for_request_keeps_an_explicit_url_test() {
  let site =
    meta.site_from("app", option.Some("https://app.test"))
    |> meta.for_request(request.new())

  site.url |> should.equal(option.Some("https://app.test"))
}

pub fn preview_renders_og_and_twitter_tags_test() {
  let html =
    meta.site_from("app", option.Some("https://app.test"))
    |> meta.with_description("A Gleam app")
    |> meta.with_image("/static/og.png")
    |> meta.preview_html

  html |> string.contains("property=\"og:title\"") |> should.be_true
  html |> string.contains("property=\"og:image\"") |> should.be_true
  html |> string.contains("https://app.test/static/og.png") |> should.be_true
  html |> string.contains("name=\"twitter:card\"") |> should.be_true
  html |> string.contains("summary_large_image") |> should.be_true
  html |> string.contains("name=\"description\"") |> should.be_true
}
