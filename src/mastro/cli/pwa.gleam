/// `mastro pwa [--bump] [--force]` — install the PWA assets.
///
/// Copies `amarra.js`, the placeholder brand icons and `og.png` from the
/// framework, writes `manifest.webmanifest`, and creates `sw.js`. Without
/// `--force` an existing file is left alone, so an app that restyled its
/// brand keeps it; `--force` resets the brand and the cache version.
import gleam/io
import gleam/list
import mastro/cli/project
import mastro/pwa
import simplifile
import wisp

pub fn run(args: List(String)) {
  let bump = list.contains(args, "--bump")
  let force = list.contains(args, "--force")
  let app = project.app_name()

  let assert Ok(_) = simplifile.create_directory_all("priv/static/js")
  let assert Ok(_) = simplifile.create_directory_all("priv/static/icons")

  install_amarra_js(force)
  install_manifest(app, force)
  install_service_worker(app, bump, force)
  install_icons(force)

  io.println("PWA assets ready.")
}

fn install_amarra_js(force: Bool) {
  copy_asset("static/js/amarra.js", "priv/static/js/amarra.js", force)
}

fn install_manifest(app: String, force: Bool) {
  let path = "priv/static/manifest.webmanifest"
  case keep_existing(path, force) {
    True -> Nil
    False -> write(path, pwa.manifest(app))
  }
}

fn install_service_worker(app: String, bump: Bool, force: Bool) {
  let path = "priv/static/js/sw.js"
  case simplifile.read(path) {
    Error(_) -> write(path, pwa.service_worker(app, 1))
    Ok(content) ->
      case force, bump {
        True, _ -> write(path, pwa.service_worker(app, 1))
        False, True ->
          case pwa.bump_cache_version(content) {
            Ok(next) -> write(path, next)
            Error(_) -> io.println("  sw.js has no CACHE_VERSION to bump")
          }
        False, False -> Nil
      }
  }
}

fn install_icons(force: Bool) {
  copy_asset("pwa/icon-192.png", "priv/static/icons/icon-192.png", force)
  copy_asset("pwa/icon-512.png", "priv/static/icons/icon-512.png", force)
  copy_asset(
    "pwa/icon-512-maskable.png",
    "priv/static/icons/icon-512-maskable.png",
    force,
  )
  copy_asset("pwa/og.png", "priv/static/og.png", force)
}

fn keep_existing(path: String, force: Bool) -> Bool {
  case simplifile.read(path), force {
    Ok(_), False -> True
    _, _ -> False
  }
}

fn copy_asset(source: String, dest: String, force: Bool) {
  case keep_existing(dest, force) {
    True -> Nil
    False -> {
      let assert Ok(priv) = wisp.priv_directory("mastro")
      case simplifile.copy(priv <> "/" <> source, dest) {
        Ok(_) -> io.println("  wrote " <> dest)
        Error(error) ->
          io.println(
            "  could not write "
            <> dest
            <> ": "
            <> simplifile.describe_error(error),
          )
      }
    }
  }
}

fn write(path: String, content: String) {
  case simplifile.write(path, content) {
    Ok(_) -> io.println("  wrote " <> path)
    Error(error) ->
      io.println(
        "  could not write " <> path <> ": " <> simplifile.describe_error(error),
      )
  }
}
