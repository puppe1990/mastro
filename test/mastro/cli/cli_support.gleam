/// Shared helpers for the CLI integration tests.
///
import gleam/result
import gleam/string
import simplifile

pub fn in_temp_dir(name: String, f: fn(String) -> Nil) -> Nil {
  let dir = "/tmp/mastro_test_" <> name
  let _ = simplifile.delete_all([dir])
  let assert Ok(_) = simplifile.create_directory_all(dir)
  f(dir)
  let _ = simplifile.delete_all([dir])
  Nil
}

pub fn file_exists(path: String) -> Bool {
  case simplifile.read(path) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn path_exists(path: String) -> Bool {
  simplifile.is_file(path) |> result.unwrap(False)
}

pub fn file_contains(path: String, substring: String) -> Bool {
  case simplifile.read(path) {
    Ok(content) -> string.contains(content, substring)
    Error(_) -> False
  }
}

@external(erlang, "mastro_test_ffi", "set_cwd")
pub fn set_cwd(path: String) -> Result(Nil, Nil)

@external(erlang, "mastro_test_ffi", "current_directory")
pub fn current_directory() -> Result(String, Nil)
