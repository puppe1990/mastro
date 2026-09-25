//// Persistent sessions.
////
//// The token is opaque and random; the row lives in the app's database, so
//// a session survives a restart and can be revoked. Expiry lives in the row:
//// once it is gone the cookie is worthless, even if it was stolen.
////
//// The store talks SQL through callbacks, the same shape `mastro/migrate`
//// uses, so the shipped module carries no driver dependency. `now` is always
//// passed in — the app decides what time it is, tests can travel.
////
//// ```gleam
//// import mastro/session
////
//// let session = session.rotate(store, user.id, session.now())?
//// wisp.redirect("/")
//// |> session.set_cookie(session.token, secure: cfg.env == config.Prod)
//// ```

import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/cookie
import gleam/http/response
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import wisp.{type Request, type Response}

/// The cookie the session token travels in.
pub const cookie_name = "_mastro_session"

/// A session lives a week. The cookie max-age matches it.
pub fn ttl_seconds() -> Int {
  60 * 60 * 24 * 7
}

pub type Session {
  Session(token: String, user_id: String, expires_at: Int, inserted_at: Int)
}

/// The table, ready to drop into a migration. Expiry is indexed because
/// loading and pruning both filter on it.
pub const create_table_sql = "CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  inserted_at INTEGER NOT NULL
)"

pub const create_index_sql = "CREATE INDEX IF NOT EXISTS sessions_expires_at_index ON sessions (expires_at)"

/// What `prune` runs, spelled out for the `db prune-sessions` command.
pub const prune_sql = "DELETE FROM sessions WHERE expires_at <= ?"

/// The SQL port. An app binds these to its own connection; tests bind them
/// to a dictionary.
pub type Store {
  Store(
    insert: fn(Session) -> Result(Nil, String),
    find: fn(String) -> Result(Option(Session), String),
    delete: fn(String) -> Result(Nil, String),
    /// Delete the rows expired as of the given time, returning how many.
    delete_expired: fn(Int) -> Result(Int, String),
    /// Delete every session a user has, returning how many.
    delete_for_user: fn(String) -> Result(Int, String),
  )
}

/// The current unix time in seconds.
pub fn now() -> Int {
  system_time_seconds()
}

/// A fresh token and an expiry one TTL away.
pub fn create(
  store: Store,
  user_id: String,
  now: Int,
) -> Result(Session, String) {
  let session =
    Session(
      token: generate(),
      user_id: user_id,
      expires_at: now + ttl_seconds(),
      inserted_at: now,
    )

  store.insert(session)
  |> result.replace(session)
}

/// The session behind a token, unless the row is missing or has expired.
pub fn load(
  store: Store,
  token: String,
  now: Int,
) -> Result(Option(Session), String) {
  use session <- result.try(store.find(token))

  case session {
    Some(s) ->
      case s.expires_at > now {
        True -> Ok(Some(s))
        False -> Ok(None)
      }
    None -> Ok(None)
  }
}

/// Log a user in: every session they had is dropped, then a new one is
/// issued, so the token that was on the wire before cannot be reused.
pub fn rotate(
  store: Store,
  user_id: String,
  now: Int,
) -> Result(Session, String) {
  use _ <- result.try(store.delete_for_user(user_id))
  create(store, user_id, now)
}

/// Drop one session, for a logout on that device.
pub fn revoke(store: Store, token: String) -> Result(Nil, String) {
  store.delete(token)
}

/// Delete the rows that expired as of `now`, returning how many went.
pub fn prune(store: Store, now: Int) -> Result(Int, String) {
  store.delete_expired(now)
}

// -- Cookies ------------------------------------------------------------------

/// Put the token on the response. `secure` is the app's production switch,
/// not the request scheme: a terminating proxy should not decide it.
pub fn set_cookie(
  resp: Response,
  token: String,
  secure secure: Bool,
) -> Response {
  let attributes =
    cookie.Attributes(
      ..cookie.defaults(http.Http),
      secure: secure,
      max_age: Some(ttl_seconds()),
    )

  response.set_cookie(
    resp,
    cookie_name,
    bit_array.base64_encode(<<token:utf8>>, False),
    attributes,
  )
}

/// Expire the cookie, for a logout.
pub fn clear_cookie(resp: Response) -> Response {
  let attributes =
    cookie.Attributes(..cookie.defaults(http.Http), max_age: Some(0))

  response.set_cookie(resp, cookie_name, "", attributes)
}

/// The token the request carried, when there is one.
pub fn token_from_cookie(req: Request) -> Option(String) {
  case wisp.get_cookie(req, cookie_name, wisp.PlainText) {
    Ok(token) if token != "" -> Some(token)
    _ -> None
  }
}

// -- Middleware ---------------------------------------------------------------

/// Load the session the request carries, if any, and hand it to the
/// handler. An expired row reads as no session at all.
pub fn load_session(
  req: Request,
  store: Store,
  now: Int,
  next: fn(Option(Session)) -> Response,
) -> Response {
  case token_from_cookie(req) {
    None -> next(None)
    Some(token) ->
      case load(store, token, now) {
        Ok(session) -> next(session)
        Error(_) -> next(None)
      }
  }
}

/// Require a session, sending an anonymous visitor to `redirect_to`.
pub fn require_auth(
  req: Request,
  store: Store,
  now: Int,
  redirect_to: String,
  next: fn(Session) -> Response,
) -> Response {
  require_auth_with(
    req,
    store,
    now,
    fn(_) { True },
    fn() { wisp.redirect(redirect_to) },
    next,
  )
}

/// Require a session that satisfies `allowed`; anything else gets the
/// `denied` response, which is where a forbidden page belongs.
pub fn require_auth_with(
  req: Request,
  store: Store,
  now: Int,
  allowed: fn(Session) -> Bool,
  denied: fn() -> Response,
  next: fn(Session) -> Response,
) -> Response {
  case token_from_cookie(req) {
    None -> denied()
    Some(token) ->
      case load(store, token, now) {
        Ok(Some(session)) ->
          case allowed(session) {
            True -> next(session)
            False -> denied()
          }
        _ -> denied()
      }
  }
}

// -- Internals ----------------------------------------------------------------

fn generate() -> String {
  crypto.strong_random_bytes(32)
  |> bit_array.base16_encode
  |> string.lowercase
}

@external(erlang, "mastro_rate_limit_ffi", "system_time_seconds")
fn system_time_seconds() -> Int
