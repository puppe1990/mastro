/// Demo seed helpers for generated repos: parent rows and sample values.
///
import gleam/list
import gleam/result
import gleam/string
import mastro/cli/text
import simplifile

/// The statements that make sure every referenced parent has a row the
/// demo child can point at: the parent demo seed when it ships one,
/// otherwise the first row it already has.
pub fn parent_seed_statements(
  app: String,
  references: List(String),
  db_arg: String,
) -> String {
  references
  |> list.unique
  |> list.map(fn(parent) {
    case parent_has_seed(app, parent) {
      True ->
        "      use "
        <> parent
        <> "_id <- result.try("
        <> parent
        <> "_repo.seed_demo("
        <> db_arg
        <> "))\n"
      False ->
        "      use "
        <> parent
        <> " <- result.try(case "
        <> parent
        <> "_repo.list("
        <> db_arg
        <> ", \"\", \"\", \"\", 1) {\n"
        <> "        ["
        <> parent
        <> ", ..] -> Ok("
        <> parent
        <> ")\n"
        <> "        [] -> Error(Nil)\n"
        <> "      })\n"
    }
  })
  |> string.join("")
}

/// The Params values a demo row carries: a reference field points at the
/// parent row the seed just prepared, the rest is a fixed sample.
pub fn seed_params(
  app: String,
  type_name: String,
  fields: List(#(String, String)),
  references: List(String),
) -> String {
  let params =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      let value = case is_reference(field_name, references) {
        True ->
          case parent_has_seed(app, string.drop_end(field_name, 3)) {
            True -> field_name
            False -> string.drop_end(field_name, 3) <> ".id"
          }
        False -> seed_value(field_type, field_name)
      }
      field_name <> ": " <> value
    })
    |> string.join(", ")

  type_name <> "Params(" <> params <> ")"
}

pub fn seed_value(field_type: String, field_name: String) -> String {
  case field_type {
    "int" -> "1"
    "float" -> "1.0"
    "bool" -> "True"
    "date" -> "\"2026-01-01\""
    "datetime" -> "\"2026-01-01T00:00:00Z\""
    _ -> "\"Demo " <> text.capitalize(field_name) <> "\""
  }
}

pub fn is_reference(field_name: String, references: List(String)) -> Bool {
  string.ends_with(field_name, "_id")
  && list.contains(references, string.drop_end(field_name, 3))
}

/// Whether the parent resource was generated at all.
pub fn parent_repo_exists(app: String, parent: String) -> Bool {
  simplifile.is_file("src/" <> app <> "/data/" <> parent <> "_repo.gleam")
  |> result.unwrap(False)
}

/// Whether the parent resource ships a demo seed a child can call. Without
/// one the child references the first row the parent already has.
pub fn parent_has_seed(app: String, parent: String) -> Bool {
  case simplifile.read("src/" <> app <> "/data/" <> parent <> "_repo.gleam") {
    Ok(content) -> string.contains(content, "pub fn seed_demo(")
    Error(_) -> False
  }
}
