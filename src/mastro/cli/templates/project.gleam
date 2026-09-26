/// File templates for the scaffold's project files.
///
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}

pub fn gleam_toml(name: String, db: DbChoice) -> String {
  let db_dep = case db {
    Postgres -> "\npog = \">= 4.1.0 and < 5.0.0\""
    Sqlite -> "\nsqlight = \">= 1.0.0 and < 2.0.0\""
    NoDb -> ""
  }

  "name = \"" <> name <> "\"
version = \"0.1.0\"
target = \"erlang\"
gleam = \">= 1.14.0\"

[dependencies]
# gleam_stdlib 0.71 removed list.range, which glisten 8.0.3 — the version
# mist 5.x requires — still calls (rawhat/glisten#54). Lift this cap when a
# glisten 8.x patch lands, or when mastro moves to mist 6 and stdlib 1.x.
gleam_stdlib = \">= 0.44.0 and < 0.71.0\"
gleam_erlang = \">= 0.34.0 and < 2.0.0\"
gleam_http = \">= 4.3.0 and < 5.0.0\"
argv = \">= 1.0.2 and < 2.0.0\"
envoy = \">= 1.1.0 and < 2.0.0\"
mist = \">= 5.0.0 and < 6.0.0\"
wisp = \">= 2.2.0 and < 3.0.0\"
lustre = \">= 5.6.0 and < 6.0.0\"
gleam_json = \">= 3.1.0 and < 4.0.0\"
mastro = \">= 0.1.0 and < 1.0.0\"" <> db_dep <> "

[dev-dependencies]
gleeunit = \">= 1.0.0 and < 2.0.0\"
"
}

pub fn gitignore() -> String {
  "/build/
.DS_Store
"
}

pub fn readme(name: String) -> String {
  "# " <> name <> "

A web application built with [Mastro](https://github.com/puppe1990/mastro).

## Development

```bash
gleam run    # Start the server at http://localhost:4000
gleam test   # Run tests
```
"
}
