/// The generated SQL migration for a resource.
///
import gleam/dict
import gleam/list
import gleam/string
import mastro/cli/gen/fields
import mastro/cli/text
import mastro/cli/types.{type DbChoice, Sqlite}

pub fn resource_migration(
  name: String,
  fields: List(#(String, String)),
  db: DbChoice,
  references: List(String),
) -> String {
  let reference_tables =
    dict.from_list(
      references
      |> list.map(fn(parent) { #(parent <> "_id", parent <> "s") }),
    )

  let column_defs =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      case dict.get(reference_tables, field_name) {
        Ok(parent_table) ->
          "  "
          <> field_name
          <> " INTEGER NOT NULL REFERENCES "
          <> parent_table
          <> "(id)"
        Error(_) -> {
          let sql_type = case db {
            Sqlite -> fields.to_sql_type_sqlite(field_type)
            _ -> fields.to_sql_type(field_type)
          }
          "  " <> field_name <> " " <> sql_type <> " NOT NULL"
        }
      }
    })
    |> string.join(",\n")

  let table = text.singularize(name) <> "s"

  case db {
    Sqlite -> "-- up
CREATE TABLE " <> table <> " (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
" <> column_defs <> ",
  inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
-- down
DROP TABLE " <> table <> ";
"
    _ -> "-- up
CREATE TABLE " <> table <> " (
  id SERIAL PRIMARY KEY,
" <> column_defs <> ",
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- down
DROP TABLE " <> table <> ";
"
  }
}
