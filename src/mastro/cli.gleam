/// Mastro CLI entry point.
///
/// Run with: gleam run -m mastro/cli
///
import argv
import gleam/io
import gleam/string
import mastro/cli/assets
import mastro/cli/build
import mastro/cli/component
import mastro/cli/console
import mastro/cli/db
import mastro/cli/destroy
import mastro/cli/dev
import mastro/cli/doctor
import mastro/cli/gen
import mastro/cli/jobs_cmd
import mastro/cli/link
import mastro/cli/migrate_cmd
import mastro/cli/new
import mastro/cli/pwa
import mastro/cli/routes
import mastro/cli/seed
import mastro/cli/upgrade

pub fn main() {
  case argv.load().arguments {
    ["new", name, ..flags] -> new.run(name, flags)
    ["gen", "page", name, ..] -> gen.page(name)
    ["gen", "resource", name, ..fields] -> gen.resource(name, fields)
    ["gen", "migration", name, ..] -> gen.migration(name)
    ["gen", "auth", ..] -> gen.auth()
    ["gen", "island", name, ..] -> gen.island(name)
    ["gen", "live", name, ..] -> gen.live(name)
    ["gen", "component", "--list", ..] -> component.run("", ["--list"])
    ["gen", "component", stem, ..flags] -> component.run(stem, flags)
    ["destroy", "auth", ..flags] -> destroy.run("auth", "", flags)
    ["destroy", kind, name, ..flags] -> destroy.run(kind, name, flags)
    ["routes", ..args] -> routes.run(args)
    ["migrate", ..] -> migrate_cmd.run()
    ["db", ..args] -> db.run(args)
    ["jobs", ..args] -> jobs_cmd.run(args)
    ["build", ..] -> build.run()
    ["pwa", ..args] -> pwa.run(args)
    ["assets", "setup", ..] -> assets.setup()
    ["assets", "build", ..] -> assets.build()
    ["assets", ..] -> assets.setup()
    ["seed", ..] -> seed.run()
    ["dev", ..] -> dev.run()
    ["doctor", ..args] -> doctor.run(args)
    ["link", ..args] -> link.run(args)
    ["upgrade", ..args] -> upgrade.run(args)
    ["console", ..] -> console.run([])
    ["help", ..] | ["--help", ..] | ["-h", ..] -> print_help()
    ["version", ..] | ["--version", ..] | ["-v", ..] ->
      io.println("mastro 0.2.0")
    [cmd, ..] -> {
      io.println("Unknown command: " <> cmd)
      io.println("")
      print_help()
    }
    [] -> print_help()
  }
}

fn print_help() {
  io.println(string.join(
    [
      "mastro — A convention-first web framework for Gleam",
      "",
      "Usage: mastro <command> [options]",
      "",
      "Commands:",
      "  new <name>                        Create a new project",
      "    --db postgres                   Add PostgreSQL support",
      "    --db sqlite                     Add SQLite support",
      "",
      "  gen page <name>                   Generate a page (handler + route)",
      "  gen resource <name> <fields...>   Generate CRUD resource",
      "    --api                           JSON API mode (no views)",
      "    --belongs-to <parent>           Add foreign key to parent",
      "  gen migration <name>              Generate a SQL migration file",
      "  gen auth                          Generate starter authentication",
      "  gen island <name>                 Generate a Lustre interactive island",
      "  gen live <name>                   Generate a Lustre server component",
      "  gen component <stem>              Seed a kit component override (--list, --dry-run)",
      "  destroy <kind> <name>             Remove generated files (--dry-run)",
      "    kinds: resource, handler, model, migration, auth",
      "",
      "  routes [--verbose]                Print the route table",
      "  migrate                           Run pending migrations",
      "  db <status|rollback|prune-sessions|seed>",
      "                                    Database commands",
      "  jobs <work|status|retry|discard|prune>",
      "                                    Run and inspect the job queue",
      "  seed                              Run database seeds",
      "  build                             Compile Lustre islands to JS",
      "  pwa [--bump] [--force]            Install PWA assets (manifest, sw.js, icons)",
      "  assets setup                      Set up Tailwind CSS",
      "  assets build                      Build CSS/JS assets",
      "  dev                               Start the dev server",
      "  doctor [--mobile]                 Check the app against the Amarra contract",
      "  console                           Open the app REPL",
      "  link [path] [--unlink]            Point gleam.toml at a local framework",
      "  upgrade [version] [--dry-run]     Bump the framework and run doctor",
      "",
      "  help                              Show this help",
      "  version                           Show version",
      "",
      "Field types for gen resource:",
      "  string, text, int, float, bool, date, datetime",
      "",
      "Examples:",
      "  mastro new my_app --db postgres",
      "  mastro gen resource posts title:string body:text published:bool",
      "  mastro gen page about",
    ],
    "\n",
  ))
}
