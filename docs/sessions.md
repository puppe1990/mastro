# Sessions

A session is a row in your database, not a signed cookie. The cookie
carries an opaque token; the row carries the user, the expiry and the
right to exist. Expiring a row logs the session out everywhere it was
used, and a stolen cookie stops working the moment the row goes.

| Where | What |
|-------|------|
| Cookie | `_mastro_session`, random 32-byte token, `HttpOnly`, `SameSite=Lax` |
| Table | `sessions (token, user_id, expires_at, inserted_at)` |
| Lifetime | 7 days (`session.ttl_seconds()`), matching the cookie `Max-Age` |

## The table

`session.create_table_sql` and `session.create_index_sql` are ready to
drop into a migration:

```sql
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  inserted_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS sessions_expires_at_index ON sessions (expires_at);
```

## The store

`session.Store` is a record of five functions. Bind them to your
connection — the shipped module has no driver dependency, so the same
module works for Pog and Sqlight:

```gleam
import mastro/session
import sqlight

fn store(conn: sqlight.Connection) -> session.Store {
  session.Store(
    insert: fn(s) { /* INSERT INTO sessions ... */ },
    find: fn(token) { /* SELECT ... WHERE token = ? */ },
    delete: fn(token) { /* DELETE ... WHERE token = ? */ },
    delete_expired: fn(now) { /* DELETE ... WHERE expires_at <= ? */ },
    delete_for_user: fn(user_id) { /* DELETE ... WHERE user_id = ? */ },
  )
}
```

`session.prune_sql` is the same delete `prune` issues, spelled out for the
`mastro db prune-sessions` command.

## Time is an argument

Nothing in the module reads the clock on its own except `session.now()`:
every call takes `now`. That is what makes an expired session testable
without waiting a week.

```gleam
let session = session.create(store, "user:1", 1_000)?
session.load(store, session.token, 1_000)   // -> Ok(Some(session))
session.load(store, session.token, session.expires_at + 1)  // -> Ok(None)
```

Expired rows are ignored on read, so a session that has not been pruned
yet still fails to authenticate. `prune` is housekeeping, not security.

## Login, logout, rotation

```gleam
// Log in: every session the user had is dropped, then a new one is issued,
// so the token that was on the wire before cannot be reused.
let session = session.rotate(store, user.id, session.now())?
wisp.redirect("/")
|> session.set_cookie(session.token, secure: config.is_production(cfg))

// Log out on this device only.
let assert Ok(_) = session.revoke(store, token)
wisp.redirect("/") |> session.clear_cookie()
```

`secure` is the app's production switch, not the request scheme: a TLS
terminating proxy should not be what decides whether the cookie is marked
`Secure`.

## Middleware

```gleam
pub fn dashboard(req: Request, ctx: Context) -> Response {
  use user <- session.require_auth(req, ctx.sessions, session.now(), "/login")
  // ...
}
```

`load_session` hands the session (or `None`) to the handler without
requiring it, and `require_auth_with` takes a predicate for the cases
where being logged in is not enough:

```gleam
use session <- session.require_auth_with(
  req,
  ctx.sessions,
  session.now(),
  fn(session) { session.user_id == owner_id },
  fn() { wisp.response(403) },
)
```
