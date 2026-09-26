import gleeunit/should
import mastro/cli/text

pub fn singularize_handles_the_common_cases_test() {
  text.singularize("posts") |> should.equal("post")
  text.singularize("categories") |> should.equal("category")
  text.singularize("buses") |> should.equal("bus")
  text.singularize("news") |> should.equal("new")
}

pub fn capitalize_uppercases_the_first_grapheme_test() {
  text.capitalize("posts") |> should.equal("Posts")
  text.capitalize("") |> should.equal("")
}
