import gleam/string
import gleeunit/should
import mastro/pwa

pub fn manifest_splits_any_and_maskable_icons_test() {
  let manifest = pwa.manifest("my_app")

  manifest |> string.contains("\"purpose\":\"any\"") |> should.be_true
  manifest |> string.contains("\"purpose\":\"maskable\"") |> should.be_true
  manifest |> string.contains("192x192") |> should.be_true
  manifest |> string.contains("512x512") |> should.be_true
  manifest
  |> string.contains("/static/icons/icon-512-maskable.png")
  |> should.be_true
}

pub fn service_worker_has_a_version_and_network_first_amarra_test() {
  let sw = pwa.service_worker("my_app", 1)

  sw |> string.contains("CACHE_VERSION = 1") |> should.be_true
  sw |> string.contains("network-first") |> should.be_true
  sw |> string.contains("/static/js/amarra.js") |> should.be_true
}

pub fn cache_version_reads_the_current_value_test() {
  pwa.cache_version(pwa.service_worker("app", 7)) |> should.equal(Ok(7))
}

pub fn cache_version_is_error_without_the_line_test() {
  pwa.cache_version("// no version here") |> should.equal(Error(Nil))
}

pub fn bump_increments_the_cache_version_test() {
  let bumped = pwa.bump_cache_version(pwa.service_worker("app", 3))

  let assert Ok(content) = bumped
  content |> string.contains("CACHE_VERSION = 4") |> should.be_true
  content |> string.contains("CACHE_VERSION = 3") |> should.be_false
}

pub fn bump_is_error_without_the_line_test() {
  pwa.bump_cache_version("// nothing") |> should.equal(Error(Nil))
}
