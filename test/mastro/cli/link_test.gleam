import gleeunit/should
import mastro/cli/link

pub fn set_path_dependency_links_the_checkout_test() {
  link.set_path_dependency(
    "[dependencies]\nmastro = \">= 0.1.0 and < 1.0.0\"\n",
    "../mastro",
  )
  |> should.equal("[dependencies]\nmastro = { path = \"../mastro\" }\n")
}

pub fn remove_path_dependency_restores_the_published_line_test() {
  link.remove_path_dependency(
    "[dependencies]\nmastro = { path = \"../mastro\" }\n",
  )
  |> should.equal("[dependencies]\n" <> link.published <> "\n")
}

pub fn other_dependencies_are_untouched_test() {
  link.set_path_dependency("mist = \">= 5.0.0\"\nmastro = \"x\"\n", "..")
  |> should.equal("mist = \">= 5.0.0\"\nmastro = { path = \"..\" }\n")
}
