import gleam/string
import gleeunit/should
import mastro/cli/component
import mastro/cli/destroy

pub fn override_module_mirrors_the_contract_test() {
  let source = component.override_module("locale-toggle")

  source |> string.contains("pub fn render(") |> should.be_true
  source |> string.contains("component locale-toggle") |> should.be_true
  source
  |> string.contains("view.with_component(reg, \"locale-toggle\", render)")
  |> should.be_true
}

pub fn singularize_handles_the_common_cases_test() {
  destroy.singularize("posts") |> should.equal("post")
  destroy.singularize("categories") |> should.equal("category")
  destroy.singularize("buses") |> should.equal("bus")
  destroy.singularize("news") |> should.equal("new")
}
