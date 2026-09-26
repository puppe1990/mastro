/// The flags that change what `gen resource` ships.
///
import gleam/io
import gleam/list
import gleam/string
import mastro/cli/types.{type AdminAuth, BearerAuth, SessionAuth}

pub type ResourceOptions {
  ResourceOptions(
    public: Bool,
    paginate: Bool,
    seed: Bool,
    admin_auth: AdminAuth,
  )
}

pub fn parse_resource_options(args: List(String)) -> ResourceOptions {
  ResourceOptions(
    public: list.contains(args, "--public"),
    paginate: list.contains(args, "--paginate"),
    seed: !list.contains(args, "--no-seed"),
    admin_auth: parse_admin_auth(flag_value(args, "--admin-auth")),
  )
}

/// Unknown values fall back to session auth and say so on stdout.
fn parse_admin_auth(value: Result(String, Nil)) -> AdminAuth {
  case value {
    Ok("bearer") -> BearerAuth
    Ok("session") -> SessionAuth
    Ok(other) -> {
      io.println("Unknown --admin-auth " <> other <> ", using session.")
      SessionAuth
    }
    Error(_) -> SessionAuth
  }
}

pub fn auth_label(auth: AdminAuth) -> String {
  case auth {
    SessionAuth -> "session"
    BearerAuth -> "bearer"
  }
}

pub fn describe_options(options: ResourceOptions) -> String {
  let parts = [
    case options.public {
      True -> "public"
      False -> "admin"
    },
    case options.paginate {
      True -> "paginate"
      False -> "no-paginate"
    },
    case options.seed {
      True -> "seed"
      False -> "no-seed"
    },
    "admin-auth=" <> auth_label(options.admin_auth),
  ]
  string.join(parts, ", ")
}

/// The value that follows `flag`, or `Error` when the flag is absent.
pub fn flag_value(args: List(String), flag: String) -> Result(String, Nil) {
  case args {
    [] -> Error(Nil)
    [f, value, ..] if f == flag -> Ok(value)
    [_, ..rest] -> flag_value(rest, flag)
  }
}
