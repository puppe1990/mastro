import gleam/string
import gleeunit/should
import lustre/element
import mastro/layout

pub fn morph_targets_test() {
  let html = layout.app(element.text("content"), "Title")
  should.be_true(string.contains(html, "id=\"amarra-nav\""))
  should.be_true(string.contains(html, "id=\"amarra-main\""))
  should.be_true(string.contains(html, "id=\"amarra-toast-host\""))
  should.be_true(string.contains(html, "content"))
}

pub fn fouc_snippet_test() {
  let html = layout.app(element.text("x"), "Title")
  should.be_true(string.contains(html, "localStorage.getItem(\"amarra-theme\")"))
  should.be_true(string.contains(html, "classList.add(\"light\")"))
  should.equal(layout.theme_key, "amarra-theme")
}

pub fn csrf_meta_tag_test() {
  let html = layout.app_with_csrf("tok-123", element.text("x"), "Title")
  should.be_true(string.contains(html, "name=\"csrf-token\""))
  should.be_true(string.contains(html, "content=\"tok-123\""))
}

pub fn plain_layout_has_no_csrf_meta_test() {
  let html = layout.app(element.text("x"), "Title")
  should.be_false(string.contains(html, "csrf-token"))
}
