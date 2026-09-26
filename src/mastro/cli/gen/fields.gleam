/// Field types the CLI parses and the Gleam/SQL types they map to.
///
import gleam/list
import gleam/string

pub fn parse_fields(raw: List(String)) -> List(#(String, String)) {
  raw
  |> list.filter_map(fn(field) {
    case string.split(field, ":") {
      [name, field_type] -> Ok(#(name, field_type))
      _ -> Error(Nil)
    }
  })
}

pub fn to_gleam_type(field_type: String) -> String {
  case field_type {
    "string" -> "String"
    "text" -> "String"
    "int" -> "Int"
    "float" -> "Float"
    "bool" -> "Bool"
    "date" -> "String"
    "datetime" -> "String"
    _ -> "String"
  }
}

pub fn to_sql_type(field_type: String) -> String {
  case field_type {
    "string" -> "TEXT"
    "text" -> "TEXT"
    "int" -> "INTEGER"
    "float" -> "DOUBLE PRECISION"
    "bool" -> "BOOLEAN"
    "date" -> "DATE"
    "datetime" -> "TIMESTAMPTZ"
    _ -> "TEXT"
  }
}

pub fn to_sql_type_sqlite(field_type: String) -> String {
  case field_type {
    "string" -> "TEXT"
    "text" -> "TEXT"
    "int" -> "INTEGER"
    "float" -> "REAL"
    "bool" -> "INTEGER"
    "date" -> "TEXT"
    "datetime" -> "TEXT"
    _ -> "TEXT"
  }
}

pub fn form_default_value(field_type: String) -> String {
  case field_type {
    "bool" -> "False"
    "int" -> "0"
    "float" -> "0.0"
    _ -> "\"\""
  }
}
