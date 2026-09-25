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
