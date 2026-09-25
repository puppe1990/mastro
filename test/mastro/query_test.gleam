import gleam/dict
import gleam/option
import gleeunit/should
import mastro/query

const allowed = ["id", "title", "published"]

pub fn parse_reads_and_decodes_pairs_test() {
  query.parse(option.Some("q=hello+world&sort=title&dir=desc"))
  |> should.equal(
    dict.from_list([
      #("q", "hello+world"),
      #("sort", "title"),
      #("dir", "desc"),
    ]),
  )
}

pub fn parse_decodes_percent_escapes_test() {
  query.parse(option.Some("q=a%20b"))
  |> should.equal(dict.from_list([#("q", "a b")]))
}

pub fn parse_without_a_query_is_empty_test() {
  query.parse(option.None) |> should.equal(dict.new())
  query.parse(option.Some("")) |> should.equal(dict.new())
}

pub fn parse_keeps_a_key_without_a_value_test() {
  query.parse(option.Some("flag"))
  |> should.equal(dict.from_list([#("flag", "")]))
}

pub fn order_by_accepts_a_whitelisted_column_test() {
  query.order_by("title", "desc", allowed, "id")
  |> should.equal("ORDER BY title desc")
}

pub fn order_by_falls_back_on_an_unknown_column_test() {
  query.order_by("password", "asc", allowed, "id")
  |> should.equal("ORDER BY id asc")
}

pub fn order_by_normalises_the_direction_test() {
  query.order_by("title", "DESC; DROP TABLE posts", allowed, "id")
  |> should.equal("ORDER BY title asc")
  query.order_by("title", "desc", allowed, "id")
  |> should.equal("ORDER BY title desc")
}

pub fn like_pattern_wraps_and_escapes_test() {
  query.like_pattern("100%_done") |> should.equal("%100\\%\\_done%")
}

pub fn offset_is_never_negative_test() {
  query.offset(1, 25) |> should.equal(0)
  query.offset(3, 25) |> should.equal(50)
  query.offset(0, 25) |> should.equal(0)
  query.offset(-4, 25) |> should.equal(0)
}

pub fn total_pages_rounds_up_and_never_zero_test() {
  query.total_pages(0, 25) |> should.equal(1)
  query.total_pages(1, 25) |> should.equal(1)
  query.total_pages(25, 25) |> should.equal(1)
  query.total_pages(26, 25) |> should.equal(2)
}
