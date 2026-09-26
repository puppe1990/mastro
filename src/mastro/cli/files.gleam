/// Filesystem helpers for the generators.
///
import gleam/list
import gleam/string
import simplifile

/// Create the parent directory of `path` so writing the file cannot fail
/// on a directory the generator has not created yet.
pub fn ensure_dir_for(path: String) {
  case string.split(path, "/") {
    [] -> Nil
    parts -> {
      let dir =
        parts
        |> list.take(list.length(parts) - 1)
        |> string.join("/")
      let _ = simplifile.create_directory_all(dir)
      Nil
    }
  }
}
