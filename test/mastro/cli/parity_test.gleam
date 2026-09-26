import gleam/string
import gleeunit/should
import mastro/cli/component

pub fn override_module_mirrors_the_contract_test() {
  let source = component.override_module("locale-toggle")

  source |> string.contains("pub fn render(") |> should.be_true
  source |> string.contains("component locale-toggle") |> should.be_true
  source
  |> string.contains("view.with_component(reg, \"locale-toggle\", render)")
  |> should.be_true
}
