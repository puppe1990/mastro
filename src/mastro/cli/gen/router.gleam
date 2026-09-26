/// Patches `router.gleam` for each generator: handler imports and routes.
///
import gleam/string
import mastro/cli/gen/gleam_file
import mastro/cli/gen/options
import simplifile

pub fn patch_page(app: String, name: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/" <> name <> "_handler"
  let content = gleam_file.add_import(content, import_line)

  let route_line =
    "    [\""
    <> name
    <> "\"], http.Get -> "
    <> name
    <> "_handler.index(req, ctx)"

  let content = add_route(content, route_line)

  let assert Ok(_) = simplifile.write(router_path, content)
}

pub fn patch_resource(
  app: String,
  plural: String,
  singular: String,
  options: options.ResourceOptions,
) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/" <> singular <> "_handler"
  let content = gleam_file.add_import(content, import_line)

  // The admin routes are gated in the handler; `--public` adds the list
  // anyone can read.
  let public_route = case options.public {
    True ->
      "\n    [\""
      <> plural
      <> "\"], http.Get -> "
      <> singular
      <> "_handler.public_index(req, ctx)"
    False -> ""
  }

  let routes =
    public_route
    <> "\n    [\"admin\", \""
    <> plural
    <> "\"], http.Get -> "
    <> singular
    <> "_handler.index(req, ctx)
    [\"admin\", \""
    <> plural
    <> "\", \"new\"], http.Get -> "
    <> singular
    <> "_handler.new(req, ctx)
    [\"admin\", \""
    <> plural
    <> "\"], http.Post -> "
    <> singular
    <> "_handler.create(req, ctx)
    [\"admin\", \""
    <> plural
    <> "\", id], http.Get -> "
    <> singular
    <> "_handler.show(req, ctx, id)
    [\"admin\", \""
    <> plural
    <> "\", id, \"edit\"], http.Get -> "
    <> singular
    <> "_handler.edit(req, ctx, id)
    [\"admin\", \""
    <> plural
    <> "\", id], http.Put -> "
    <> singular
    <> "_handler.update(req, ctx, id)
    [\"admin\", \""
    <> plural
    <> "\", id], http.Delete -> "
    <> singular
    <> "_handler.delete(req, ctx, id)"

  let content = add_route(content, routes)

  let assert Ok(_) = simplifile.write(router_path, content)
}

pub fn patch_api_resource(app: String, plural: String, singular: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/" <> singular <> "_handler"
  let content = gleam_file.add_import(content, import_line)

  // API routes: no /new or /edit (those are HTML-only)
  let routes =
    "\n    [\"api\", \""
    <> plural
    <> "\"], http.Get -> "
    <> singular
    <> "_handler.index(req, ctx)
    [\"api\", \""
    <> plural
    <> "\"], http.Post -> "
    <> singular
    <> "_handler.create(req, ctx)
    [\"api\", \""
    <> plural
    <> "\", id], http.Get -> "
    <> singular
    <> "_handler.show(req, ctx, id)
    [\"api\", \""
    <> plural
    <> "\", id], http.Put -> "
    <> singular
    <> "_handler.update(req, ctx, id)
    [\"api\", \""
    <> plural
    <> "\", id], http.Delete -> "
    <> singular
    <> "_handler.delete(req, ctx, id)"

  let content = add_route(content, routes)
  let assert Ok(_) = simplifile.write(router_path, content)
}

pub fn patch_live(app: String, name: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let handler_import = "import " <> app <> "/web/" <> name <> "_live_handler"
  let content = gleam_file.add_import(content, handler_import)

  let socket_import = "import " <> app <> "/web/live/" <> name <> "_socket"
  let content = gleam_file.add_import(content, socket_import)

  let routes =
    "\n    [\""
    <> name
    <> "\"], http.Get -> "
    <> name
    <> "_live_handler.index(req, ctx)"

  let content = add_route(content, routes)
  let assert Ok(_) = simplifile.write(router_path, content)
}

pub fn patch_auth(app: String) {
  let router_path = "src/" <> app <> "/router.gleam"
  let assert Ok(content) = simplifile.read(router_path)

  let import_line = "import " <> app <> "/web/auth_handler"
  let content = gleam_file.add_import(content, import_line)

  let routes =
    "\n    [\"login\"], http.Get -> auth_handler.login_page(req, ctx)
    [\"login\"], http.Post -> auth_handler.login(req, ctx)
    [\"register\"], http.Get -> auth_handler.register_page(req, ctx)
    [\"register\"], http.Post -> auth_handler.register(req, ctx)
    [\"logout\"], http.Post -> auth_handler.logout(req, ctx)"

  let content = add_route(content, routes)

  let assert Ok(_) = simplifile.write(router_path, content)
}

/// Insert routes before the catch-all pattern, or leave the file untouched
/// when neither catch-all shape is present.
fn add_route(content: String, route_line: String) -> String {
  case string.split_once(content, "    _, _ ->") {
    Ok(#(before, after)) -> before <> route_line <> "\n    _, _ ->" <> after
    Error(_) ->
      case string.split_once(content, "    _ ->") {
        Ok(#(before, after)) -> before <> route_line <> "\n    _ ->" <> after
        Error(_) -> content
      }
  }
}
