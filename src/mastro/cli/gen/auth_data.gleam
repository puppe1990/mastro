/// Templates for the auth generator's domain, repo and migration files.
///
pub fn auth_user_type() -> String {
  "pub type User {
  User(id: Int, email: String, hashed_password: String)
}
"
}

pub fn auth_domain(_app: String) -> String {
  "import gleam/crypto
import gleam/bit_array
import gleam/string

/// Hash a password using a simple HMAC-based approach.
/// Replace with a proper bcrypt/argon2 library for production.
pub fn hash_password(password: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(password))
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Verify a password against a hash.
pub fn verify_password(password: String, hash: String) -> Bool {
  hash_password(password) == hash
}
"
}

pub fn auth_user_repo(app: String) -> String {
  let q = "\""
  "import gleam/dynamic/decode
import gleam/result
import " <> app <> "/domain/user.{type User, User}
import pog

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use email <- decode.field(1, decode.string)
  use hashed_password <- decode.field(2, decode.string)
  decode.success(User(id: id, email: email, hashed_password: hashed_password))
}

pub fn get_by_email(db: pog.Connection, email: String) -> Result(User, Nil) {
  pog.query(" <> q <> "SELECT id, email, hashed_password FROM users WHERE email = $1" <> q <> ")
  |> pog.parameter(pog.text(email))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn get_by_id(db: pog.Connection, id: Int) -> Result(User, Nil) {
  pog.query(" <> q <> "SELECT id, email, hashed_password FROM users WHERE id = $1" <> q <> ")
  |> pog.parameter(pog.int(id))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}

pub fn create(
  db: pog.Connection,
  email: String,
  hashed_password: String,
) -> Result(User, Nil) {
  pog.query(
    " <> q <> "INSERT INTO users (email, hashed_password) VALUES ($1, $2) RETURNING id, email, hashed_password" <> q <> ",
  )
  |> pog.parameter(pog.text(email))
  |> pog.parameter(pog.text(hashed_password))
  |> pog.returning(user_decoder())
  |> pog.execute(db)
  |> result.replace_error(Nil)
  |> result.try(fn(r) {
    case r.rows {
      [user] -> Ok(user)
      _ -> Error(Nil)
    }
  })
}
"
}

pub fn auth_migration() -> String {
  "-- up
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  hashed_password TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX users_email_index ON users (email);
-- down
DROP TABLE users;
"
}
