/// `mastro gen component <stem> [--list] [--dry-run]`
///
/// Seeds an app-owned override for a shipped kit component, so the app
/// restyles the real contract instead of recreating it. In the Lustre view
/// layer an override is a module registered with `view.with_component`
/// (see ADR 0001), so the file carries the component's `(attrs, inner)`
/// shape rather than an HTML partial.
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/format
import mastro/cli/project
import mastro/kit
import simplifile

pub fn run(stem: String, flags: List(String)) {
  case list.contains(flags, "--list") || stem == "" {
    True -> list.each(kit.required_stems, io.println)
    False -> seed(stem, list.contains(flags, "--dry-run"))
  }
}

fn seed(stem: String, dry_run: Bool) {
  let app = project.app_name()
  let file_stem = string.replace(stem, "-", "_")
  let path = "src/" <> app <> "/web/components/" <> file_stem <> ".gleam"
  let content = override_module(stem)

  case dry_run {
    True -> io.println("would create " <> path)
    False -> {
      let assert Ok(_) =
        simplifile.create_directory_all("src/" <> app <> "/web/components")
      let assert Ok(_) = simplifile.write(path, content)
      format.format_files([path])
      io.println("Created " <> path)
    }
  }
}

/// The shipped contract, spelled out with a generic slot the app can fill.
pub fn override_module(stem: String) -> String {
  "//// Override for the `" <> stem <> "` kit component.
////
//// Mirrors the shipped contract: `(attrs, inner) -> Element`. Register it
//// with `view.with_component(reg, \"" <> stem <> "\", render)`.
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn render(
  _attrs: List(#(String, String)),
  inner: Element(Nil),
) -> Element(Nil) {
  html.div([attribute.class(\"component " <> stem <> "\")], [inner])
}
"
}
