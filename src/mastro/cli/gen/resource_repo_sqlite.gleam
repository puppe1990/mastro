/// The generated repo module for SQLite (sqlight).
///
import gleam/int
import gleam/list
import gleam/string
import mastro/cli/gen/resource_references
import mastro/cli/gen/resource_seed

pub fn resource_repo_sqlite(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  references: List(String),
  sortable: List(String),
  display: String,
  seed: Bool,
) -> String {
  let table = resource_singular <> "s"
  let field_names = list.map(fields, fn(f) { f.0 }) |> string.join(", ")
  let select_fields = "id, " <> field_names
  let q = "\""
  let sortable_literal = resource_references.string_list_literal(sortable)
  let options_fns = resource_references.reference_option_fns(references)
  let count_fn = repo_count_sqlite(table, display, q)
  let parent_imports = case seed {
    True -> resource_references.reference_imports(app_name, references)
    False -> ""
  }
  let params_import = case seed {
    True -> ".{type " <> type_name <> "Params, " <> type_name <> "Params}"
    False -> ".{type " <> type_name <> "Params}"
  }
  let seed_fns = case seed {
    True -> "/// The demo row for development: inserted once, when the table is
/// empty. Returns its id so a child resource can reference it.
pub fn seed_demo(db_path: String) -> Result(Int, Nil) {
  case count(db_path, \"\") {
    0 -> {
" <> resource_seed.parent_seed_statements(app_name, references, "db_path") <> "      use item <- result.try(create(db_path, " <> resource_seed.seed_params(
        app_name,
        type_name,
        fields,
        references,
      ) <> "))
      Ok(item.id)
    }
    _ -> first_id(db_path)
  }
}

fn first_id(db_path: String) -> Result(Int, Nil) {
  case repo.query(
    db_path,
    \"SELECT id FROM " <> table <> " ORDER BY id LIMIT 1\",
    [],
    int_decoder(),
  ) {
    Ok([id, ..]) -> Ok(id)
    _ -> Error(Nil)
  }
}

"
    False -> ""
  }

  let decoder_fields =
    fields
    |> list.index_map(fn(f, i) {
      let #(name, field_type) = f
      let decode_fn = case field_type {
        "bool" -> "sqlight.decode_bool()"
        "int" -> "decode.int"
        "float" -> "decode.float"
        _ -> "decode.string"
      }
      "  use "
      <> name
      <> " <- decode.field("
      <> int.to_string(i + 1)
      <> ", "
      <> decode_fn
      <> ")"
    })
    |> string.join("\n")

  let constructor_args =
    fields
    |> list.map(fn(f) { f.0 <> ": " <> f.0 })
    |> string.join(", ")

  let insert_placeholders =
    fields
    |> list.index_map(fn(_, _i) { "?" })
    |> string.join(", ")

  let insert_params =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let sq_fn = case field_type {
        "bool" -> "sqlight.bool"
        "int" -> "sqlight.int"
        "float" -> "sqlight.float"
        _ -> "sqlight.text"
      }
      "    " <> sq_fn <> "(params." <> name <> "),"
    })
    |> string.join("\n")

  let update_sets =
    fields
    |> list.index_map(fn(f, _i) { f.0 <> " = ?" })
    |> string.join(", ")

  string.join(
    [
      "import gleam/dynamic/decode",
      "import gleam/result",
      "import "
        <> app_name
        <> "/domain/"
        <> resource_singular
        <> ".{type "
        <> type_name
        <> ", "
        <> type_name
        <> "}",
      "import "
        <> app_name
        <> "/web/forms/"
        <> resource_singular
        <> "_form"
        <> params_import
        <> case parent_imports {
        "" -> ""
        imports -> "\n" <> imports
      },
      "import " <> app_name <> "/data/repo",
      "import mastro/query",
      "import sqlight",
      "",
      "fn "
        <> resource_singular
        <> "_decoder() -> decode.Decoder("
        <> type_name
        <> ") {",
      "  use id <- decode.field(0, decode.int)",
      decoder_fields,
      "  decode.success("
        <> type_name
        <> "(id: id, "
        <> constructor_args
        <> "))",
      "}",
      "",
      "/// Search (LIKE on " <> display <> "), a whitelisted sort and a page.",
      "pub fn list(",
      "  db_path: String,",
      "  search: String,",
      "  sort: String,",
      "  dir: String,",
      "  page: Int,",
      ") -> List(" <> type_name <> ") {",
      "  let order = query.order_by(sort, dir, "
        <> sortable_literal
        <> ", \"id\")",
      "  let offset = query.offset(page, query.per_page)",
      "  case repo.query(",
      "    db_path,",
      "    "
        <> q
        <> "SELECT "
        <> select_fields
        <> " FROM "
        <> table
        <> " WHERE "
        <> display
        <> " LIKE ? "
        <> q
        <> " <> order <> "
        <> q
        <> " LIMIT ? OFFSET ?"
        <> q
        <> ",",
      "    [",
      "      sqlight.text(query.like_pattern(search)),",
      "      sqlight.int(query.per_page),",
      "      sqlight.int(offset),",
      "    ],",
      "    " <> resource_singular <> "_decoder(),",
      "  ) {",
      "    Ok(rows) -> rows",
      "    Error(_) -> []",
      "  }",
      "}",
      "",
      count_fn,
      seed_fns,
      options_fns,
      "",
      "pub fn get(db_path: String, id: Int) -> Result("
        <> type_name
        <> ", Nil) {",
      "  repo.query(db_path, "
        <> q
        <> "SELECT "
        <> select_fields
        <> " FROM "
        <> table
        <> " WHERE id = ?"
        <> q
        <> ", [sqlight.int(id)], "
        <> resource_singular
        <> "_decoder())",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn create(db_path: String, params: "
        <> type_name
        <> "Params) -> Result("
        <> type_name
        <> ", Nil) {",
      "  repo.query(",
      "    db_path,",
      "    "
        <> q
        <> "INSERT INTO "
        <> table
        <> " ("
        <> field_names
        <> ") VALUES ("
        <> insert_placeholders
        <> ") RETURNING "
        <> select_fields
        <> q
        <> ",",
      "    [",
      insert_params,
      "    ],",
      "    " <> resource_singular <> "_decoder(),",
      "  )",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn update(",
      "  db_path: String,",
      "  id: Int,",
      "  params: " <> type_name <> "Params,",
      ") -> Result(" <> type_name <> ", Nil) {",
      "  repo.query(",
      "    db_path,",
      "    "
        <> q
        <> "UPDATE "
        <> table
        <> " SET "
        <> update_sets
        <> " WHERE id = ? RETURNING "
        <> select_fields
        <> q
        <> ",",
      "    [",
      insert_params,
      "      sqlight.int(id),",
      "    ],",
      "    " <> resource_singular <> "_decoder(),",
      "  )",
      "  |> result.replace_error(Nil)",
      "  |> result.try(fn(rows) {",
      "    case rows {",
      "      [item] -> Ok(item)",
      "      _ -> Error(Nil)",
      "    }",
      "  })",
      "}",
      "",
      "pub fn delete(db_path: String, id: Int) -> Result(Nil, Nil) {",
      "  repo.query(db_path, "
        <> q
        <> "DELETE FROM "
        <> table
        <> " WHERE id = ?"
        <> q
        <> ", [sqlight.int(id)], decode.success(Nil))",
      "  |> result.replace(Nil)",
      "  |> result.replace_error(Nil)",
      "}",
      "",
    ],
    "\n",
  )
}

/// The SQLite spelling of the total the pagination needs.
fn repo_count_sqlite(table: String, display: String, q: String) -> String {
  "/// A single integer column, decoded from its row.
fn int_decoder() -> decode.Decoder(Int) {
  use value <- decode.field(0, decode.int)
  decode.success(value)
}

/// How many rows the search matches: the total the pagination needs.
pub fn count(db_path: String, search: String) -> Int {
  case repo.query(
    db_path,
    \"SELECT COUNT(*) FROM " <> table <> " WHERE " <> display <> " LIKE ?\",
    [sqlight.text(query.like_pattern(search))],
    int_decoder(),
  ) {
    Ok([total, ..]) -> total
    _ -> 0
  }
}

"
}
