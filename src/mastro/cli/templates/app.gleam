/// File templates for the generated app's modules and tests.
///
import mastro/cli/types.{type DbChoice, NoDb, Postgres, Sqlite}

pub fn main_module(name: String, db: DbChoice) -> String {
  let db_import = case db {
    Postgres | Sqlite -> "\nimport " <> name <> "/data/repo"
    NoDb -> ""
  }

  let db_open = case db {
    Postgres -> "\n  let assert Ok(db) = repo.connect(cfg)"
    Sqlite -> "\n  let db_path = repo.database_path(cfg)"
    NoDb -> ""
  }

  let ctx_args = case db {
    Postgres -> "config: cfg, db: db, logs: logs"
    Sqlite -> "config: cfg, db_path: db_path, logs: logs"
    NoDb -> "config: cfg, logs: logs"
  }

  "import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import " <> name <> "/config
import " <> name <> "/context
import " <> name <> "/router
import mastro/dev_log
import mastro/net
import mastro/security
import wisp
import wisp/wisp_mist" <> db_import <> "

pub fn main() {
  wisp.configure_logger()

  let cfg = config.load()

  case config.validate(cfg) {
    Ok(_) -> Nil
    Error(errors) -> panic as security.describe(errors)
  }

  let logs =
    dev_log.start(
      200,
      dev_log.options(config.log_json(cfg), config.is_development(cfg)),
    )
  dev_log.install(logs)

  // A busy preferred port should not stop the dev server; take the next free.
  let port = net.pick_port(cfg.port, 10)
  // Keep the resolved port in config so /health reports the URL that answers.
  let cfg = config.Config(..cfg, port: port, port_string: int.to_string(port))" <> db_open <> "
  let ctx = context.Context(" <> ctx_args <> ")

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, ctx), cfg.secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start

  io.println(net.banner(\"" <> name <> "\", port))
  process.sleep_forever()
}
"
}

pub fn config_module(name: String) -> String {
  "import envoy
import gleam/int
import gleam/list
import gleam/option.{type Option, from_result}
import gleam/result
import gleam/string
import mastro/i18n
import mastro/meta
import mastro/security

/// The package name, known at generation time.
pub const app_name = \"" <> name <> "\"

pub type Config {
  Config(
    port: Int,
    port_string: String,
    secret_key_base: String,
    env: Env,
    log_format: LogFormat,
    locale: i18n.Locale,
    app_url: Option(String),
    admin_token: Option(String),
    trusted_proxies: List(String),
  )
}

pub type Env {
  Dev
  Test
  Prod
}

/// Request/SQL logs are JSON in development unless `LOG_FORMAT=text`.
pub type LogFormat {
  Text
  Json
}

pub fn load() -> Config {
  let port =
    envoy.get(\"PORT\")
    |> result.try(int.parse)
    |> result.unwrap(4000)

  let secret_key_base =
    envoy.get(\"SECRET_KEY_BASE\")
    |> result.unwrap(
      \"dev-secret-key-base-that-is-at-least-64-bytes-long-for-security!!\",
    )

  let env = case envoy.get(\"APP_ENV\") {
    Ok(\"prod\") -> Prod
    Ok(\"test\") -> Test
    _ -> Dev
  }

  let log_format = case envoy.get(\"LOG_FORMAT\") {
    Ok(\"text\") -> Text
    Ok(\"json\") -> Json
    Ok(_) -> default_log_format(env)
    Error(_) -> default_log_format(env)
  }

  let locale = i18n.parse(envoy.get(\"LOCALE\") |> result.unwrap(\"en\"))

  Config(
    port: port,
    port_string: int.to_string(port),
    secret_key_base: secret_key_base,
    env: env,
    log_format: log_format,
    locale: locale,
    app_url: from_result(envoy.get(\"APP_URL\")),
    admin_token: from_result(envoy.get(\"ADMIN_TOKEN\")),
    trusted_proxies: split_list(envoy.get(\"TRUSTED_PROXIES\")),
  )
}

fn default_log_format(env: Env) -> LogFormat {
  case env {
    Dev -> Json
    _ -> Text
  }
}

pub fn is_production(cfg: Config) -> Bool {
  cfg.env == Prod
}

pub fn is_development(cfg: Config) -> Bool {
  cfg.env == Dev
}

pub fn log_json(cfg: Config) -> Bool {
  cfg.log_format == Json
}

/// The site metadata a page renders: app name plus the configured URL.
pub fn site(cfg: Config) -> meta.Site {
  meta.site_from(app_name, cfg.app_url)
}

/// Translate a UI string with the configured locale.
pub fn t(cfg: Config, key: String) -> String {
  i18n.t(cfg.locale, key)
}

/// The boot gate. `admin_routes` is `True` once the app serves bearer
/// admin routes, which makes `ADMIN_TOKEN` mandatory in production.
pub fn validate(cfg: Config) -> Result(Nil, List(security.Error)) {
  security.validate(
    production: is_production(cfg),
    app_url: cfg.app_url,
    admin_token: cfg.admin_token,
    admin_routes: False,
  )
}

fn split_list(value: Result(String, Nil)) -> List(String) {
  case value {
    Ok(value) ->
      value
      |> string.split(\",\")
      |> list.map(string.trim)
      |> list.filter(fn(item) { item != \"\" })
    Error(_) -> []
  }
}
"
}

pub fn context_module(name: String, db: DbChoice) -> String {
  let db_field = case db {
    Postgres -> ", db: pog.Connection"
    Sqlite -> ", db_path: String"
    NoDb -> ""
  }

  let db_import = case db {
    Postgres -> "\nimport pog"
    _ -> ""
  }

  "import " <> name <> "/config" <> db_import <> "
import mastro/dev_log

pub type Context {
  Context(config: config.Config" <> db_field <> ", logs: dev_log.Store)
}
"
}

pub fn repo_module(name: String, db: DbChoice) -> String {
  case db {
    Postgres -> "import " <> name <> "/config.{type Config}
import gleam/erlang/process
import gleam/result
import pog

pub fn connect(cfg: Config) -> Result(pog.Connection, Nil) {
  let db_url = case cfg.env {
    config.Test -> \"postgres://localhost:5432/" <> name <> "_test\"
    _ -> \"postgres://localhost:5432/" <> name <> "_dev\"
  }

  let pool_name = process.new_name(prefix: \"" <> name <> "_db\")
  use db_config <- result.try(pog.url_config(pool_name, db_url))
  case pog.start(db_config) {
    Ok(_started) -> Ok(pog.named_connection(pool_name))
    Error(_) -> Error(Nil)
  }
}
"
    Sqlite -> "import gleam/dynamic/decode
import gleam/list
import " <> name <> "/config.{type Config}
import mastro/dev_log
import sqlight

/// Get the SQLite database path for the current environment.
pub fn database_path(cfg: Config) -> String {
  case cfg.env {
    config.Test -> \":memory:\"
    _ -> \"" <> name <> ".db\"
  }
}

/// Run a query on a fresh connection, recording it in the dev log so the
/// console (and the `/logs` viewer) shows the SQL the app ran.
pub fn query(
  db_path: String,
  sql: String,
  params: List(sqlight.Value),
  expecting: decode.Decoder(a),
) -> Result(List(a), sqlight.Error) {
  use conn <- sqlight.with_connection(db_path)
  let start = dev_log.now_ms()
  let result = sqlight.query(sql, on: conn, with: params, expecting: expecting)
  dev_log.sql(sql, list.length(params), dev_log.now_ms() - start)
  result
}
"
    NoDb -> ""
  }
}

pub fn main_test(_name: String) -> String {
  "import gleeunit

pub fn main() {
  gleeunit.main()
}
"
}

pub fn home_handler_test(_name: String) -> String {
  "import gleeunit/should

pub fn placeholder_test() {
  1 + 1
  |> should.equal(2)
}
"
}
