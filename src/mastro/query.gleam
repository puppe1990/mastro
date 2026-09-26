//// Helpers for generated index pages: a safe `ORDER BY`, a `LIKE`
//// pattern and pagination math.
////
//// Sort is the dangerous one: `?sort=` comes from the query string, so it
//// is only accepted when the column is in the resource's whitelist. An
//// unknown column or direction falls back to the default, never into SQL.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/uri

pub const default_direction = "asc"

/// Decode a query string into a dictionary. `a=1&b=two` becomes
/// `#("a", "1"), #("b", "two")`. A repeated key keeps the last value, which
/// is enough for `q`, `sort`, `dir` and `page`.
pub fn parse(query_string: Option(String)) -> Dict(String, String) {
  case query_string {
    option.None -> dict.new()
    option.Some(raw) ->
      raw
      |> string.split("&")
      |> list.filter(fn(pair) { pair != "" })
      |> list.fold(dict.new(), fn(acc, pair) {
        case string.split_once(pair, "=") {
          Ok(#(key, value)) -> dict.insert(acc, decode(key), decode(value))
          Error(_) -> dict.insert(acc, decode(pair), "")
        }
      })
  }
}

fn decode(value: String) -> String {
  uri.percent_decode(value) |> result.unwrap(value)
}

/// A link base for sort and pagination links: the path plus the params that
/// must survive them (`q`, `sort`, `dir`). Empty values drop out and the
/// values are percent-encoded, so the base is a valid URL on its own and
/// `mastro/kit` can append `&sort=` / `&page=` to it.
pub fn url(path: String, params: List(#(String, String))) -> String {
  let query =
    params
    |> list.filter(fn(pair) { pair.1 != "" })
    |> list.map(fn(pair) {
      uri.percent_encode(pair.0) <> "=" <> uri.percent_encode(pair.1)
    })
    |> string.join("&")

  case query {
    "" -> path
    _ -> path <> "?" <> query
  }
}

/// `ORDER BY <column> <direction>`, or `ORDER BY <default> asc` when the
/// caller's column is not in `allowed` or the direction is not asc/desc.
pub fn order_by(
  sort: String,
  dir: String,
  allowed: List(String),
  default: String,
) -> String {
  case list.contains(allowed, sort) {
    False -> "ORDER BY " <> default <> " " <> default_direction
    True -> "ORDER BY " <> sort <> " " <> direction(dir)
  }
}

/// Normalise a sort direction. Anything that is not `desc` is `asc`, so a
/// garbage value cannot reach the statement.
pub fn direction(dir: String) -> String {
  case string.lowercase(string.trim(dir)) {
    "desc" -> "desc"
    _ -> default_direction
  }
}

/// A `LIKE` pattern for a search box: `%term%`, with `%` and `_` escaped so
/// they match literally.
pub fn like_pattern(term: String) -> String {
  let escaped =
    term
    |> string.replace("\\", "\\\\")
    |> string.replace("%", "\\%")
    |> string.replace("_", "\\_")
  "%" <> escaped <> "%"
}

pub const per_page = 25

/// The offset for a 1-based page number, never negative.
pub fn offset(page_number: Int, size: Int) -> Int {
  let safe_page = case page_number < 1 {
    True -> 1
    False -> page_number
  }
  { safe_page - 1 } * size
}

/// The number of pages for `total` rows, at least one.
pub fn total_pages(total: Int, size: Int) -> Int {
  case size <= 0 {
    True -> 1
    False -> {
      let pages = { total + size - 1 } / size
      case pages < 1 {
        True -> 1
        False -> pages
      }
    }
  }
}
