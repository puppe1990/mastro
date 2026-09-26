/// Shared types for the CLI.
///
pub type DbChoice {
  Postgres
  Sqlite
  NoDb
}

/// How a generated resource guards its admin routes.
pub type AdminAuth {
  /// The signed `_user_id` cookie the auth generator writes.
  SessionAuth
  /// `ADMIN_TOKEN` in an `Authorization: Bearer` header.
  BearerAuth
}
