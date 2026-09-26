/// `gen auth` — users, sessions, forms, handlers, middleware and tests.
///
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/format
import mastro/cli/gen/auth_data
import mastro/cli/gen/auth_web
import mastro/cli/gen/migration
import mastro/cli/gen/router
import mastro/cli/project
import simplifile

pub fn auth() {
  let app = project.app_name()

  list.each(
    [
      "src/" <> app <> "/web/forms",
      "src/" <> app <> "/web/middleware",
      "src/" <> app <> "/domain",
      "src/" <> app <> "/data",
      "src/" <> app <> "/data/migrations",
      "test/" <> app <> "/web",
    ],
    fn(dir) {
      let _ = simplifile.create_directory_all(dir)
    },
  )

  let files = [
    #("src/" <> app <> "/domain/user.gleam", auth_data.auth_user_type()),
    #("src/" <> app <> "/domain/auth.gleam", auth_data.auth_domain(app)),
    #("src/" <> app <> "/data/user_repo.gleam", auth_data.auth_user_repo(app)),
    #(
      "src/"
        <> app
        <> "/data/migrations/"
        <> migration.next_migration_number(app)
        <> "_create_users.sql",
      auth_data.auth_migration(),
    ),
    #("src/" <> app <> "/web/forms/auth_form.gleam", auth_web.auth_form(app)),
    #("src/" <> app <> "/web/auth_handler.gleam", auth_web.auth_handler(app)),
    #("src/" <> app <> "/web/auth_views.gleam", auth_web.auth_views(app)),
    #(
      "src/" <> app <> "/web/middleware/auth.gleam",
      auth_web.auth_middleware(app),
    ),
    #("test/" <> app <> "/web/auth_handler_test.gleam", auth_web.auth_test(app)),
  ]

  list.each(files, fn(file) {
    let #(path, content) = file
    let assert Ok(_) = simplifile.write(path, content)
  })

  let _ = router.patch_auth(app)
  let router_path = "src/" <> app <> "/router.gleam"
  let gleam_paths =
    list.filter_map(files, fn(file) {
      case string.ends_with(file.0, ".gleam") {
        True -> Ok(file.0)
        False -> Error(Nil)
      }
    })
  format.format_files([router_path, ..gleam_paths])

  io.println("")
  io.println("Created:")
  list.each(files, fn(file) { io.println("  " <> file.0) })
  io.println("")
  io.println("Updated:")
  io.println("  src/" <> app <> "/router.gleam")
  io.println("")
  io.println("Note: You need a password hashing library. Add one with:")
  io.println("  gleam add beecrypt")
}
