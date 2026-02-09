import app/domain/users/sqlite as users
import gleam/result
import gleam/option.{type Option}
import fpo/types.{type Session}
import fpo/db/parrot as db
import fpo/monad/app.{type App}
import app/sql
import app/types.{type Config} as _
import gleam/bit_array
import fpo/generic/crypto.{hash_sha256_base64} as _

pub type User = users.User

pub fn authenticate(
  session session: Session,
  cfg cfg: Config,
) -> Option(User) {
  use token <- option.then(session.user_token)

  use token <- option.then(bit_array.base64_decode(token) |> option.from_result)

  token
  |> hash_sha256_base64
  |> sql.get_user_by(hashed_token: _ )
  |> db.one_or_sqlite(conn: cfg.sqlite_conn, to_err: fn(_err) { Nil }, err: Nil)
  |> result.map(users.from_get_user_by_to_user)
  |> option.from_result
}

pub fn insert_user_token(
  user user: User,
  hashed_token hashed_token: String,
) -> App(Result(sql.InsertUserToken, Nil), Config, pubsub, User) {
  users.insert_session_token(user:, hashed_token:)
}

pub fn delete_user_token(
  hashed_token hashed_token: String,
) -> App(Result(sql.DeleteUserToken, Nil), Config, pubsub, user) {
  users.delete_session_token(hashed_token:)
}
