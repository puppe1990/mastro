/// The generated form module: display state, decoder and defaults.
///
import gleam/list
import gleam/string
import mastro/cli/gen/fields
import mastro/cli/text

pub fn resource_form(
  app_name: String,
  resource_singular: String,
  type_name: String,
  fields: List(#(String, String)),
) -> String {
  let form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      let default_value = fields.form_default_value(field_type)
      "    " <> field_name <> ": " <> default_value <> ","
    })
    |> string.join("\n")

  let form_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> fields.to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let params_field_defs =
    fields
    |> list.map(fn(f) {
      let #(name, ft) = f
      "    " <> name <> ": " <> fields.to_gleam_type(ft) <> ","
    })
    |> string.join("\n")

  let from_form_fields =
    fields
    |> list.map(fn(f) {
      let #(field_name, field_type) = f
      case field_type {
        "bool" ->
          "    "
          <> field_name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> field_name
          <> "\" }),"
        "int" ->
          "    "
          <> field_name
          <> ": result.unwrap(int.parse(get_value(data, \""
          <> field_name
          <> "\")), 0),"
        "float" ->
          "    "
          <> field_name
          <> ": result.unwrap(float.parse(get_value(data, \""
          <> field_name
          <> "\")), 0.0),"
        _ ->
          "    " <> field_name <> ": get_value(data, \"" <> field_name <> "\"),"
      }
    })
    |> string.join("\n")

  let from_record_fields =
    fields
    |> list.map(fn(f) {
      let #(name, _) = f
      "    " <> name <> ": item." <> name <> ","
    })
    |> string.join("\n")

  let decode_lets =
    fields
    |> list.filter(fn(f) { f.1 != "bool" })
    |> list.map(fn(f) {
      let #(name, _) = f
      "  let " <> name <> " = get_value(data, \"" <> name <> "\")"
    })
    |> string.join("\n")

  let validation_lines =
    fields
    |> list.filter(fn(f) {
      let #(_, t) = f
      t == "string" || t == "text"
    })
    |> list.map(fn(f) {
      let #(name, _) = f
      "    |> validate.required("
      <> name
      <> ", \""
      <> name
      <> "\", \""
      <> text.capitalize(name)
      <> " is required\")"
    })
    |> string.join("\n")

  let params_construction =
    fields
    |> list.map(fn(f) {
      let #(name, t) = f
      case t {
        "bool" ->
          "        "
          <> name
          <> ": list.any(data.values, fn(v) { v.0 == \""
          <> name
          <> "\" }),"
        "int" ->
          "        " <> name <> ": result.unwrap(int.parse(" <> name <> "), 0),"
        "float" ->
          "        "
          <> name
          <> ": result.unwrap(float.parse("
          <> name
          <> "), 0.0),"
        _ -> "        " <> name <> ": " <> name <> ","
      }
    })
    |> string.join("\n")

  let extra_imports = case
    list.any(fields, fn(f) { f.1 == "int" }),
    list.any(fields, fn(f) { f.1 == "float" })
  {
    True, True -> "\nimport gleam/int\nimport gleam/float"
    True, False -> "\nimport gleam/int"
    False, True -> "\nimport gleam/float"
    False, False -> ""
  }

  "import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result" <> extra_imports <> "
import " <> app_name <> "/domain/" <> resource_singular <> ".{type " <> type_name <> "}
import mastro/validate
import wisp

pub type " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Option(Int),
" <> form_field_defs <> "
  )
}

pub type " <> type_name <> "Params {
  " <> type_name <> "Params(
" <> params_field_defs <> "
  )
}

pub fn empty() -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> form_fields <> "
  )
}

pub fn from_" <> resource_singular <> "(item: " <> type_name <> ") -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: Some(item.id),
" <> from_record_fields <> "
  )
}

pub fn from_form_data(data: wisp.FormData) -> " <> type_name <> "Form {
  " <> type_name <> "Form(
    id: None,
" <> from_form_fields <> "
  )
}

pub fn decode(
  data: wisp.FormData,
) -> Result(" <> type_name <> "Params, List(#(String, String))) {
" <> decode_lets <> "

  let errors =
    []
" <> validation_lines <> "

  case errors {
    [] ->
      Ok(" <> type_name <> "Params(
" <> params_construction <> "
      ))
    _ -> Error(errors)
  }
}

fn get_value(data: wisp.FormData, key: String) -> String {
  list.find(data.values, fn(v) { v.0 == key })
  |> result.map(fn(v) { v.1 })
  |> result.unwrap(\"\")
}
"
}
