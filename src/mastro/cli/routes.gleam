/// `mastro routes [--verbose]` — print the route table from router.gleam.
///
/// `--verbose` adds the middleware stack and a static warning when two
/// routes can match the same method and path shape (for example a literal
/// `/posts/new` next to `/posts/:id`).
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/project
import simplifile

pub type Route {
  Route(method: String, path: String, handler: String)
}

pub type Conflict {
  Conflict(method: String, path: String, other: String)
}

/// The middleware the scaffold installs, in the order it wraps.
pub const middleware_names = [
  "method_override",
  "dev_log.request_log",
  "dev_error.rescue",
  "security.headers",
  "serve_static",
  "csrf.issue",
]

pub fn run(args: List(String)) {
  let verbose = list.contains(args, "--verbose")
  let app = project.app_name()
  let router_path = "src/" <> app <> "/router.gleam"

  case simplifile.read(router_path) {
    Error(_) -> io.println("Could not read " <> router_path)
    Ok(content) -> {
      let routes = extract_routes(content)
      case routes {
        [] -> io.println("No routes found.")
        _ -> {
          list.each(routes, fn(route) {
            io.println(
              pad_right(route.method, 8)
              <> pad_right(route.path, 24)
              <> route.handler,
            )
          })

          case verbose {
            False -> Nil
            True -> {
              io.println("")
              io.println(
                "Middleware: " <> string.join(middleware(content), " -> "),
              )
              conflicts(routes)
              |> list.each(fn(conflict) {
                io.println(
                  "warning: "
                  <> conflict.method
                  <> " "
                  <> conflict.path
                  <> " may shadow "
                  <> conflict.other,
                )
              })
            }
          }
        }
      }
    }
  }
}

// -- Parsing ------------------------------------------------------------------

pub fn extract_routes(content: String) -> List(Route) {
  content
  |> string.split("\n")
  |> list.filter_map(fn(line) { parse_route_line(string.trim(line)) })
}

fn parse_route_line(line: String) -> Result(Route, Nil) {
  case string.split_once(line, " -> ") {
    Error(_) -> Error(Nil)
    Ok(#(pattern, handler)) ->
      case string.contains(pattern, "http.") {
        False -> Error(Nil)
        True ->
          Ok(Route(
            method: extract_method(pattern),
            path: extract_path(pattern),
            handler: extract_handler_name(handler),
          ))
      }
  }
}

fn extract_method(pattern: String) -> String {
  case string.contains(pattern, "http.Get") {
    True -> "GET"
    False ->
      case string.contains(pattern, "http.Post") {
        True -> "POST"
        False ->
          case string.contains(pattern, "http.Put") {
            True -> "PUT"
            False ->
              case string.contains(pattern, "http.Delete") {
                True -> "DELETE"
                False ->
                  case string.contains(pattern, "http.Patch") {
                    True -> "PATCH"
                    False -> "???"
                  }
              }
          }
      }
  }
}

fn extract_path(pattern: String) -> String {
  case string.split_once(pattern, "],") {
    Error(_) -> "/"
    Ok(#(list_part, _)) -> {
      let inner = string.drop_start(string.trim(list_part), 1)
      let segments =
        inner
        |> string.split(",")
        |> list.map(string.trim)
        |> list.filter(fn(segment) { segment != "" })
        |> list.map(fn(segment) {
          case string.starts_with(segment, "\"") {
            True -> string.replace(segment, "\"", "")
            False -> ":" <> segment
          }
        })

      case segments {
        [] -> "/"
        _ -> "/" <> string.join(segments, "/")
      }
    }
  }
}

fn extract_handler_name(handler: String) -> String {
  case string.split_once(handler, "(") {
    Ok(#(name, _)) -> string.trim(name)
    Error(_) -> string.trim(handler)
  }
}

// -- Conflicts ----------------------------------------------------------------

/// Pairs of routes with the same method whose paths have the same shape:
/// equal segments, or a literal against a `:param`. Such a pair can shadow
/// depending on order, so it is worth a look.
pub fn conflicts(routes: List(Route)) -> List(Conflict) {
  let remaining = routes
  routes
  |> list.index_map(fn(route, index) { #(index, route) })
  |> list.flat_map(fn(current) {
    let #(index, route) = current
    remaining
    |> list.index_map(fn(other, other_index) { #(other_index, other) })
    |> list.filter(fn(candidate) {
      let #(other_index, other) = candidate
      other_index > index
      && route.method == other.method
      && same_shape(route.path, other.path)
    })
    |> list.map(fn(candidate) {
      let #(_, other) = candidate
      Conflict(method: route.method, path: route.path, other: other.path)
    })
  })
}

fn same_shape(a: String, b: String) -> Bool {
  segments_match(segments(a), segments(b))
}

fn segments(path: String) -> List(String) {
  path |> string.split("/") |> list.filter(fn(segment) { segment != "" })
}

fn segments_match(a: List(String), b: List(String)) -> Bool {
  case a, b {
    [], [] -> True
    [x, ..xs], [y, ..ys] -> {
      let compatible = x == y || dynamic(x) || dynamic(y)
      compatible && segments_match(xs, ys)
    }
    _, _ -> False
  }
}

fn dynamic(segment: String) -> Bool {
  string.starts_with(segment, ":")
}

fn middleware(content: String) -> List(String) {
  list.filter(middleware_names, fn(name) { string.contains(content, name) })
}

fn pad_right(value: String, width: Int) -> String {
  let padding = width - string.length(value)
  case padding > 0 {
    True -> value <> string.repeat(" ", padding)
    False -> value
  }
}
