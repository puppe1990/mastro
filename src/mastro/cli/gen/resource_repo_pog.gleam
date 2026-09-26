/// The generated repo module for Postgres (pog).
///
import gleam/int
import gleam/list
import gleam/string
import mastro/cli/gen/resource_references
import mastro/cli/gen/resource_seed

pub fn resource_repo_pog(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
  references: List(String),
  sortable: List(String),
  display: String,
  seed: Bool,
) -> String {
  let field_names =
    fields
    |> list.map(fn(f) { f.0 })
    |> string.join(", ")

  let table = resource_singular <> "s"
  let select_fields = "id, " <> field_names
  let sortable_literal = resource_references.string_list_literal(sortable)
  let options_fns = resource_references.reference_option_fns_pog(references)
  let count_fn = repo_count_pog(table, display)
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
pub fn seed_demo(db: pog.Connection) -> Result(Int, Nil) {
  case count(db, \"\") {
    0 -> {
" <> resource_seed.parent_seed_statements(app_name, references, "db") <> "      use item <- result.try(create(db, " <> resource_seed.seed_params(
        app_name,
        type_name,
        fields,
        references,
      ) <> "))
      Ok(item.id)
    }
    _ -> first_id(db)
  }
}

fn first_id(db: pog.Connection) -> Result(Int, Nil) {
  let rows =
    pog.query(\"SELECT id FROM " <> table <> " ORDER BY id LIMIT 1\")
    |> pog.returning(int_decoder())
    |> pog.execute(db)
    |> result.map(fn(r) { r.rows })
    |> result.unwrap([])

  case rows {
    [id, ..] -> Ok(id)
    [] -> Error(Nil)
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
        "bool" -> "decode.bool"
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
    |> list.index_map(fn(_, i) { "$" <> int.to_string(i + 1) })
    |> string.join(", ")

  let insert_params =
    fields
    |> list.map(fn(f) {
      let #(name, field_type) = f
      let pog_fn = case field_type {
        "bool" -> "pog.bool"
        "int" -> "pog.int"
        "float" -> "pog.float"
        _ -> "pog.text"
      }
      "  |> pog.parameter(" <> pog_fn <> "(params." <> name <> "))"
    })
    |> string.join("\n")

  let update_sets =
    fields
    |> list.index_map(fn(f, i) { f.0 <> " = $" <> int.to_string(i + 1) })
    |> string.join(", ")

  let update_id_param = "$" <> int.to_string(list.length(fields) + 1)

  let q = "\""

  let get_query =
    "  pog.query("
    <> q
    <> "SELECT "
    <> select_fields
    <> " FROM "
    <> table
    <> " WHERE id = $1"
    <> q
    <> ")"

  let create_query =
    "  pog.query("
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
    <> ")"

  let update_query =
    "  pog.query("
    <> q
    <> "UPDATE "
    <> table
    <> " SET "
    <> update_sets
    <> " WHERE id = "
    <> update_id_param
    <> " RETURNING "
    <> select_fields
    <> q
    <> ")"

  let delete_query =
    "  pog.query("
    <> q
    <> "DELETE FROM "
    <> table
    <> " WHERE id = $1"
    <> q
    <> ")"

  let single_row_extract =
    "  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [item] -> Ok(item)
      _ -> Error(Nil)
    }
  })"

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
      "import mastro/query",
      "import pog",
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
      "  db: pog.Connection,",
      "  search: String,",
      "  sort: String,",
      "  dir: String,",
      "  page: Int,",
      ") -> List(" <> type_name <> ") {",
      "  let order = query.order_by(sort, dir, "
        <> sortable_literal
        <> ", \"id\")",
      "  let pattern = query.like_pattern(search)",
      "  pog.query("
        <> q
        <> "SELECT "
        <> select_fields
        <> " FROM "
        <> resource_singular
        <> "s WHERE "
        <> display
        <> " LIKE $1 "
        <> q
        <> " <> order <> "
        <> q
        <> " LIMIT $2 OFFSET $3"
        <> q
        <> ")",
      "  |> pog.parameter(pog.text(pattern))",
      "  |> pog.parameter(pog.int(query.per_page))",
      "  |> pog.parameter(pog.int(query.offset(page, query.per_page)))",
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      "  |> pog.execute(db)",
      "  |> result.map(fn(r) { r.rows })",
      "  |> result.unwrap([])",
      "}",
      "",
      count_fn,
      seed_fns,
      options_fns,
      "",
      "pub fn get(db: pog.Connection, id: Int) -> Result("
        <> type_name
        <> ", Nil) {",
      get_query,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn create(db: pog.Connection, params: "
        <> type_name
        <> "Params) -> Result("
        <> type_name
        <> ", Nil) {",
      create_query,
      insert_params,
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn update(",
      "  db: pog.Connection,",
      "  id: Int,",
      "  params: " <> type_name <> "Params,",
      ") -> Result(" <> type_name <> ", Nil) {",
      update_query,
      insert_params,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.returning(" <> resource_singular <> "_decoder())",
      single_row_extract,
      "}",
      "",
      "pub fn delete(db: pog.Connection, id: Int) -> Result(Nil, Nil) {",
      delete_query,
      "  |> pog.parameter(pog.int(id))",
      "  |> pog.execute(db)",
      "  |> result.replace(Nil)",
      "  |> result.replace_error(Nil)",
      "}",
      "",
    ],
    "\n",
  )
}

/// The Postgres spelling of the total the pagination needs.
fn repo_count_pog(table: String, display: String) -> String {
  "/// A single integer column, decoded from its row.
fn int_decoder() -> decode.Decoder(Int) {
  use value <- decode.field(0, decode.int)
  decode.success(value)
}

/// How many rows the search matches: the total the pagination needs.
pub fn count(db: pog.Connection, search: String) -> Int {
  let rows =
    pog.query(\"SELECT COUNT(*) FROM " <> table <> " WHERE " <> display <> " LIKE $1\")
    |> pog.parameter(pog.text(query.like_pattern(search)))
    |> pog.returning(int_decoder())
    |> pog.execute(db)
    |> result.map(fn(r) { r.rows })
    |> result.unwrap([])

  case rows {
    [total, ..] -> total
    [] -> 0
  }
}

"
}
