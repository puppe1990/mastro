/// Editing an existing Gleam source file: the import block.
///
import gleam/list
import gleam/string

/// Add `import_line` after the last existing import, unless it is already
/// there.
pub fn add_import(content: String, import_line: String) -> String {
  case string.contains(content, import_line) {
    True -> content
    False -> {
      let lines = string.split(content, "\n")
      let #(before, after) = split_after_imports(lines, [])
      string.join(list.append(before, [import_line, ..after]), "\n")
    }
  }
}

fn split_after_imports(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(list.reverse(acc), [])
    [line, ..rest] ->
      case string.starts_with(line, "import ") {
        True -> split_after_imports(rest, [line, ..acc])
        False ->
          case acc {
            [] -> split_after_imports(rest, [line, ..acc])
            _ -> #(list.reverse(acc), [line, ..rest])
          }
      }
  }
}
