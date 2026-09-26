/// Gleam source fragments the generators splice into generated files.
///
import gleam/string
import mastro/cli/text

/// A column label: `author_id` renders as `Author`.
pub fn field_label(field_name: String) -> String {
  case string.ends_with(field_name, "_id") {
    True -> text.capitalize(string.drop_end(field_name, 3))
    False -> text.capitalize(field_name)
  }
}

/// Gleam source that renders a field as text.
pub fn field_to_text(field_type: String, value: String) -> String {
  case field_type {
    "int" -> "int.to_string(" <> value <> ")"
    "float" -> "float.to_string(" <> value <> ")"
    "bool" -> "bool.to_string(" <> value <> ")"
    _ -> value
  }
}

/// The Gleam literal for a bool.
pub fn bool_literal(value: Bool) -> String {
  case value {
    True -> "True"
    False -> "False"
  }
}
