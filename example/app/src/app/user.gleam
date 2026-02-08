import app/domain/users/sqlite as users
import gleam/result
import gleam/option.{type Option, Some, None}
import fpo/types.{type Session, Session}
import fpo/db/parrot as db
import fpo/monad/app.{type App, pure, do}
import fpo/generic/guard
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

  use token <- option.then(bit_array.base64_decode(token) |> option.from_result)

  token
  |> hash_sha256
  |> sql.authenticate_user(hashed_token: _ )
  |> db.one_or_sqlite(conn: cfg.sqlite_conn, to_err: fn(_err) { Nil }, err: Nil)
  |> result.map(users.from_authenticate_user_to_user)
  |> option.from_result
}

pub fn sign_in(
  user user: User,
  session session: Session,
) -> App(Result(Session, Nil), Config, pubsub, User) {
  let token = crypto.strong_random_bytes(32)
  let hashed_token = hash_sha256(token)
  use result <- do(users.insert_session_token(user:, hashed_token:))

  use _token_row <- guard.ok_(result, fn(_) { pure(Error(Nil)) })

  let token_str = bit_array.base64_encode(token, True)

  pure(Ok(Session(..session, user_token: Some(token_str))))
}

pub fn sign_out(
  session session: Session,
) -> App(Session, Config, pubsub, User) {
  use token <- guard.some(session.user_token, pure(session))

  let hashed_token =
    token
    |> bit_array.from_string
    |> hash_sha256

  use _deleted <- do(users.delete_session_token(hashed_token:))

  pure(Session(..session, user_token: None))
}

//

fn hash_sha256(
  bytes bytes: BitArray,
) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_encode(False)
}
