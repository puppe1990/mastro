import gleeunit/should
import mastro/cli/upgrade

pub fn set_framework_version_rewrites_the_constraint_test() {
  upgrade.set_framework_version(
    "[dependencies]\nmastro = \">= 0.1.0 and < 1.0.0\"\n",
    "0.3.0",
  )
  |> should.equal("[dependencies]\nmastro = \">= 0.3.0 and < 1.0.0\"\n")
}

pub fn set_framework_version_leaves_other_dependencies_test() {
  upgrade.set_framework_version(
    "mist = \">= 5.0.0\"\nmastro = \"x\"\n",
    "1.2.3",
  )
  |> should.equal("mist = \">= 5.0.0\"\nmastro = \">= 1.2.3 and < 1.0.0\"\n")
}
