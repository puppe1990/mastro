/// The generated handler tests for a resource.
///
import gleam/list
import gleam/string

pub fn api_resource_test(
  _app_name: String,
  _resource_singular: String,
) -> String {
  "import gleeunit/should

pub fn placeholder_test() {
  // API handler tests require a running database.
  // Test your domain logic and JSON encoding instead.
  1 + 1
  |> should.equal(2)
}
"
}

pub fn resource_test(
  app_name: String,
  resource_singular: String,
  _type_name: String,
  fields: List(#(String, String)),
) -> String {
  // Build valid form data for decode test
  let valid_values =
    fields
    |> list.map(fn(f) {
      let #(name, ftype) = f
      let val = case ftype {
        "bool" -> "on"
        "int" -> "42"
        "float" -> "3.14"
        _ -> "test value"
      }
      "    #(\"" <> name <> "\", \"" <> val <> "\"),"
    })
    |> string.join("\n")

  // Find required string fields for missing-field test
  let required_fields =
    fields
    |> list.filter(fn(f) { f.1 == "string" || f.1 == "text" })

  let missing_field_test = case required_fields {
    [#(name, _), ..] -> "

pub fn decode_missing_" <> name <> "_returns_error_test() {
  let data =
    wisp.FormData(values: [], files: [])

  " <> resource_singular <> "_form.decode(data)
  |> should.be_error
}
"
    [] -> ""
  }

  "import gleeunit/should
import " <> app_name <> "/web/forms/" <> resource_singular <> "_form
import wisp

pub fn empty_form_has_no_id_test() {
  let form = " <> resource_singular <> "_form.empty()
  form.id
  |> should.be_none
}

pub fn decode_valid_form_test() {
  let data =
    wisp.FormData(
      values: [
" <> valid_values <> "
      ],
      files: [],
    )

  " <> resource_singular <> "_form.decode(data)
  |> should.be_ok
}
" <> missing_field_test
}
