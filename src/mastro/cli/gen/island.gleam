/// `gen island <name>` — a Lustre client island and its embed helper.
///
import gleam/io
import mastro/cli/format
import mastro/cli/project
import simplifile

pub fn island(name: String) {
  let app = project.app_name()

  let island_dir = "src/" <> app <> "/web/islands"
  let _ = simplifile.create_directory_all(island_dir)

  let island_path = island_dir <> "/" <> name <> ".gleam"
  let embed_path = island_dir <> "/" <> name <> "_embed.gleam"

  let assert Ok(_) = simplifile.write(island_path, island_module(name))
  let assert Ok(_) = simplifile.write(embed_path, island_embed(app, name))
  format.format_files([island_path, embed_path])

  io.println("")
  io.println("Created:")
  io.println("  " <> island_path)
  io.println("  " <> embed_path)
  io.println("")
  io.println("Usage in a view:")
  io.println("  import " <> app <> "/web/islands/" <> name <> "_embed")
  io.println("  " <> name <> "_embed.render()")
  io.println("  " <> name <> "_embed.script_tag()")
  io.println("")
  io.println("Build the island JS:")
  io.println("  gleam build --target javascript")
}

fn island_module(name: String) -> String {
  "/// Interactive island: " <> name <> "
///
/// This is a Lustre client-side app. Compile to JavaScript with:
///   gleam build --target javascript
///
import gleam/int
import lustre
import lustre/element.{text}
import lustre/element/html.{button, div, p}
import lustre/event

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init(_flags: Nil) -> Model {
  Model(count: 0)
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Increment -> Model(count: model.count + 1)
    Decrement -> Model(count: model.count - 1)
  }
}

pub fn view(model: Model) -> element.Element(Msg) {
  div([], [
    button([event.on_click(Decrement)], [text(\"-\")]),
    p([], [text(int.to_string(model.count))]),
    button([event.on_click(Increment)], [text(\"+\")]),
  ])
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, \"#" <> name <> "\", Nil)
}
"
}

fn island_embed(_app: String, name: String) -> String {
  "/// Server-side helper to embed the " <> name <> " island in a view.
///
import lustre/attribute.{id, src}
import lustre/element.{type Element, text}
import lustre/element/html.{div, script}

/// Render the mount point for the island.
pub fn render() -> Element(Nil) {
  div([id(\"" <> name <> "\")], [text(\"Loading...\")])
}

/// Render the script tag that loads the island JS.
pub fn script_tag() -> Element(Nil) {
  script([src(\"/static/js/islands/" <> name <> ".js\")], \"\")
}
"
}
