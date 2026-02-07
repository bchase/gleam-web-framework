import app/domain/users/sqlite as users
import gleam/result
import gleam/option.{type Option}
import fpo/types.{type Session}
import fpo/db/parrot as db
import app/sql
import app/types.{type Config} as _
//
import gleam/crypto
import gleam/bit_array

pub type User = users.User

pub fn authenticate(
  session session: Session,
  cfg cfg: Config,
) -> Option(User) {
  use token <- option.then(session.user_token)

  token
  |> bit_array.from_string
  |> hash_sha256
  |> sql.authenticate_user(hashed_token: _ )
  |> db.one_or_sqlite(conn: cfg.sqlite_conn, to_err: fn(_err) { Nil }, err: Nil)
  |> result.map(users.from_authenticate_user_to_user)
  |> option.from_result
}

//

pub const dummy_token = "foobar"

pub fn dummy_token_for_session() -> String {
  dummy_token
  |> bit_array.from_string
  |> bit_array.base64_encode(False)
}

pub fn dummy_token_hashed_for_db() -> String {
  dummy_token
  |> bit_array.from_string
  |> hash_sha256
}

//

fn hash_sha256(
  bytes bytes: BitArray,
) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_encode(False)
}
