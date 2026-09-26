/// `gen page <name>` — a handler, its test, and the router route.
///
import gleam/io
import mastro/cli/files
import mastro/cli/format
import mastro/cli/gen/router
import mastro/cli/project
import mastro/cli/text
import simplifile

pub fn page(name: String) {
  let app = project.app_name()

  let handler_path = "src/" <> app <> "/web/" <> name <> "_handler.gleam"
  let test_path = "test/" <> app <> "/web/" <> name <> "_handler_test.gleam"

  let handler_content = "import " <> app <> "/context.{type Context}
import " <> app <> "/web/layouts/root_layout
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{h1, section}
import wisp.{type Request, type Response}

pub fn index(req: Request, _ctx: Context) -> Response {
  section([class(\"" <> name <> "\")], [
    h1([], [text(\"" <> text.capitalize(name) <> "\")]),
  ])
  |> root_layout.wrap(\"" <> text.capitalize(name) <> "\", req)
  |> wisp.html_response(200)
}
"

  let test_content =
    "import gleeunit/should

pub fn placeholder_test() {
  1 + 1
  |> should.equal(2)
}
"

  let assert Ok(_) = simplifile.write(handler_path, handler_content)
  files.ensure_dir_for(test_path)
  let assert Ok(_) = simplifile.write(test_path, test_content)

  let _ = router.patch_page(app, name)
  let router_path = "src/" <> app <> "/router.gleam"
  format.format_files([handler_path, test_path, router_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> handler_path)
  io.println("  " <> test_path)
  io.println("")
  io.println("Updated:")
  io.println("  " <> router_path)
}
