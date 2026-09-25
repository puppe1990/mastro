import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/http/response
import gleam/int
import gleam/option
import gleam/otp/actor
import gleam/string
import gleeunit/should
import mastro/session
import wisp
import wisp/simulate

// -- An in-memory store -------------------------------------------------------

type Memory {
  Memory(rows: dict.Dict(String, session.Session))
}

type MemoryMessage {
  Insert(session.Session, process.Subject(Result(Nil, String)))
  Find(String, process.Subject(Result(option.Option(session.Session), String)))
  Delete(String, process.Subject(Result(Nil, String)))
  DeleteExpired(Int, process.Subject(Result(Int, String)))
  DeleteForUser(String, process.Subject(Result(Int, String)))
}

fn memory() -> process.Subject(MemoryMessage) {
  let assert Ok(started) =
    actor.new(Memory(rows: dict.new()))
    |> actor.on_message(handle_memory)
    |> actor.start

  started.data
}

fn handle_memory(
  state: Memory,
  message: MemoryMessage,
) -> actor.Next(Memory, MemoryMessage) {
  case message {
    Insert(session, reply) -> {
      process.send(reply, Ok(Nil))
      actor.continue(
        Memory(rows: dict.insert(state.rows, session.token, session)),
      )
    }

    Find(token, reply) -> {
      process.send(reply, Ok(option.from_result(dict.get(state.rows, token))))
      actor.continue(state)
    }

    Delete(token, reply) -> {
      process.send(reply, Ok(Nil))
      actor.continue(Memory(rows: dict.delete(state.rows, token)))
    }

    DeleteExpired(now, reply) -> {
      let kept =
        state.rows |> dict.filter(fn(_, session) { session.expires_at > now })

      process.send(reply, Ok(dict.size(state.rows) - dict.size(kept)))
      actor.continue(Memory(rows: kept))
    }

    DeleteForUser(user_id, reply) -> {
      let kept =
        state.rows |> dict.filter(fn(_, session) { session.user_id != user_id })

      process.send(reply, Ok(dict.size(state.rows) - dict.size(kept)))
      actor.continue(Memory(rows: kept))
    }
  }
}

fn store(memory: process.Subject(MemoryMessage)) -> session.Store {
  session.Store(
    insert: fn(session) {
      process.call_forever(memory, fn(reply) { Insert(session, reply) })
    },
    find: fn(token) {
      process.call_forever(memory, fn(reply) { Find(token, reply) })
    },
    delete: fn(token) {
      process.call_forever(memory, fn(reply) { Delete(token, reply) })
    },
    delete_expired: fn(now) {
      process.call_forever(memory, fn(reply) { DeleteExpired(now, reply) })
    },
    delete_for_user: fn(user_id) {
      process.call_forever(memory, fn(reply) { DeleteForUser(user_id, reply) })
    },
  )
}

fn must_not_run() -> wisp.Response {
  panic as "the handler must not run for a rejected request"
}

fn request_with_token(token: String) -> wisp.Request {
  simulate.cookie(
    simulate.browser_request(http.Get, "/admin"),
    session.cookie_name,
    token,
    wisp.PlainText,
  )
}

fn set_cookie_header(resp: wisp.Response) -> String {
  case response.get_header(resp, "set-cookie") {
    Ok(header) -> header
    Error(_) -> ""
  }
}

// -- Lifecycle ----------------------------------------------------------------

pub fn create_then_load_returns_the_session_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)

  should.equal(
    session.load(store, created.token, 1000),
    Ok(option.Some(created)),
  )
}

pub fn a_token_that_was_never_issued_loads_nothing_test() {
  let store = store(memory())

  should.equal(session.load(store, "never-issued", 1000), Ok(option.None))
}

pub fn expired_session_does_not_authenticate_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)
  let past_the_ttl = created.expires_at + 1

  should.equal(
    session.load(store, created.token, past_the_ttl),
    Ok(option.None),
  )
}

pub fn rotate_invalidates_the_previous_token_test() {
  let store = store(memory())
  let assert Ok(first) = session.create(store, "user:1", 1000)
  let assert Ok(second) = session.rotate(store, "user:1", 2000)

  should.not_equal(first.token, second.token)
  should.equal(session.load(store, first.token, 2000), Ok(option.None))
  should.equal(session.load(store, second.token, 2000), Ok(option.Some(second)))
}

pub fn rotate_keeps_other_users_sessions_test() {
  let store = store(memory())
  let assert Ok(other) = session.create(store, "user:2", 1000)
  let assert Ok(_) = session.rotate(store, "user:1", 2000)

  should.equal(session.load(store, other.token, 2000), Ok(option.Some(other)))
}

pub fn revoke_drops_one_session_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)
  let assert Ok(_) = session.revoke(store, created.token)

  should.equal(session.load(store, created.token, 1000), Ok(option.None))
}

pub fn prune_removes_exactly_the_expired_rows_test() {
  let store = store(memory())
  let assert Ok(old) = session.create(store, "user:1", 1000)
  let assert Ok(live_one) = session.create(store, "user:2", 2000)
  let assert Ok(live_two) = session.create(store, "user:3", 3000)

  let after_old_expired = old.expires_at + 1
  should.equal(session.prune(store, after_old_expired), Ok(1))

  should.equal(
    session.load(store, old.token, after_old_expired),
    Ok(option.None),
  )
  should.equal(
    session.load(store, live_one.token, after_old_expired),
    Ok(option.Some(live_one)),
  )
  should.equal(
    session.load(store, live_two.token, after_old_expired),
    Ok(option.Some(live_two)),
  )
}

pub fn prune_is_a_no_op_when_nothing_expired_test() {
  let store = store(memory())
  let assert Ok(_) = session.create(store, "user:1", 1000)

  should.equal(session.prune(store, 1000), Ok(0))
}

// -- Cookies ------------------------------------------------------------------

pub fn set_cookie_round_trips_through_a_request_test() {
  let request = simulate.browser_request(http.Get, "/")
  let resp = session.set_cookie(wisp.ok(), "tok-123", secure: False)
  let next = simulate.session(request, request, resp)

  should.equal(session.token_from_cookie(next), option.Some("tok-123"))
}

pub fn the_secure_flag_follows_the_app_test() {
  let insecure = session.set_cookie(wisp.ok(), "tok", secure: False)
  should.be_false(string.contains(set_cookie_header(insecure), "Secure"))

  let secure = session.set_cookie(wisp.ok(), "tok", secure: True)
  should.be_true(string.contains(set_cookie_header(secure), "Secure"))
}

pub fn the_cookie_is_http_only_and_lasts_a_week_test() {
  let header =
    session.set_cookie(wisp.ok(), "tok", secure: False) |> set_cookie_header

  should.be_true(string.contains(header, "HttpOnly"))
  should.be_true(string.contains(
    header,
    "Max-Age=" <> int.to_string(session.ttl_seconds()),
  ))
}

pub fn clear_cookie_expires_it_test() {
  let header = session.clear_cookie(wisp.ok()) |> set_cookie_header

  should.be_true(string.contains(header, "Max-Age=0"))
}

// -- Middleware ---------------------------------------------------------------

pub fn load_session_hands_the_session_over_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)

  let resp =
    session.load_session(
      request_with_token(created.token),
      store,
      1000,
      fn(found) {
        should.equal(found, option.Some(created))
        wisp.ok()
      },
    )

  should.equal(resp.status, 200)
}

pub fn load_session_treats_an_expired_row_as_anonymous_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)

  session.load_session(
    request_with_token(created.token),
    store,
    created.expires_at + 1,
    fn(found) {
      should.equal(found, option.None)
      wisp.ok()
    },
  )
}

pub fn require_auth_redirects_an_anonymous_visitor_test() {
  let store = store(memory())
  let request = simulate.browser_request(http.Get, "/admin")

  let resp =
    session.require_auth(request, store, 1000, "/login", fn(_) {
      must_not_run()
    })

  should.equal(resp.status, 303)
  should.equal(response.get_header(resp, "location"), Ok("/login"))
}

pub fn require_auth_lets_a_live_session_through_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)

  let resp =
    session.require_auth(
      request_with_token(created.token),
      store,
      1000,
      "/login",
      fn(found) {
        should.equal(found, created)
        wisp.ok()
      },
    )

  should.equal(resp.status, 200)
}

pub fn require_auth_with_denies_when_the_predicate_fails_test() {
  let store = store(memory())
  let assert Ok(created) = session.create(store, "user:1", 1000)

  let resp =
    session.require_auth_with(
      request_with_token(created.token),
      store,
      1000,
      fn(session) { session.user_id == "user:2" },
      fn() { wisp.response(403) },
      fn(_) { must_not_run() },
    )

  should.equal(resp.status, 403)
}
