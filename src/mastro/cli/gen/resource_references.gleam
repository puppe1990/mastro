/// Foreign-key helpers for generated repos: imports and option loaders.
///
import gleam/list
import gleam/string

pub fn string_list_literal(items: List(String)) -> String {
  "["
  <> string.join(list.map(items, fn(item) { "\"" <> item <> "\"" }), ", ")
  <> "]"
}

/// One import per referenced parent: the demo seed calls the parent repo.
pub fn reference_imports(app: String, references: List(String)) -> String {
  references
  |> list.unique
  |> list.map(fn(parent) { "import " <> app <> "/data/" <> parent <> "_repo" })
  |> string.join("\n")
}

/// One `<parent>_options` function per foreign key, plus the shared decoder.
pub fn reference_option_fns(references: List(String)) -> String {
  case references {
    [] -> ""
    _ ->
      references
      |> list.map(fn(parent) {
        "pub fn "
        <> parent
        <> "_options(db_path: String) -> List(#(Int, String)) {
  case repo.query(
    db_path,
    \"SELECT id, COALESCE(name, title, CAST(id AS TEXT)) FROM "
        <> parent
        <> "s\",
    [],
    option_decoder(),
  ) {
    Ok(rows) -> rows
    Error(_) -> []
  }
}

"
      })
      |> string.join("")
      |> fn(functions) {
        functions <> "fn option_decoder() -> decode.Decoder(#(Int, String)) {
  use id <- decode.field(0, decode.int)
  use label <- decode.field(1, decode.string)
  decode.success(#(id, label))
}

"
      }
  }
}

/// The Postgres spelling of the option functions.
pub fn reference_option_fns_pog(references: List(String)) -> String {
  case references {
    [] -> ""
    _ ->
      references
      |> list.map(fn(parent) {
        "pub fn "
        <> parent
        <> "_options(db: pog.Connection) -> List(#(Int, String)) {
  pog.query(\"SELECT id, COALESCE(name, title, id::text) FROM "
        <> parent
        <> "s\")
  |> pog.returning(option_decoder())
  |> pog.execute(db)
  |> result.map(fn(r) { r.rows })
  |> result.unwrap([])
}

"
      })
      |> string.join("")
      |> fn(functions) {
        functions <> "fn option_decoder() -> decode.Decoder(#(Int, String)) {
  use id <- decode.field(0, decode.int)
  use label <- decode.field(1, decode.string)
  decode.success(#(id, label))
}

"
      }
  }
}
