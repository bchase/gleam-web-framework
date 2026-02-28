import gleam/string
import app/domain/users/sqlite as users
import gleam/result
import gleam/option.{type Option, None}
import fpo/types.{type Session}
// import fpo/db/parrot as db
import fpo/db/parrot as db
import fpo/monad/app/db/parrot_sqlite.{sqlite} as _
import fpo/monad/app.{type App}
import app/sql
import app/types.{type Config} as _
import gleam/bit_array
import fpo/generic/crypto.{hash_sha256_base64} as _
import fpo/types/err as fpo
import app/types/err

pub type User = users.User

pub fn authenticate(
  session session: Session,
  cfg cfg: Config,
) -> Option(User) {
  use token <- option.then(session.user_token)

  use token <- option.then(bit_array.base64_decode(token) |> option.from_result)

  let db = sqlite(to_err: fn(err) { fpo.AppErr(err.SqlightErr(err)) })

  token
  |> hash_sha256_base64
  |> sql.get_user_by(hashed_token: _ )
  |> db.one_or(conn: cfg.sqlite_conn, err: fpo.NotFound(None), db:)
  |> result.map(users.from_get_user_by_to_user)
  |> option.from_result
}

pub fn insert_user_token(
  user user: User,
  hashed_token hashed_token: String,
) -> App(Result(sql.InsertUserToken, Nil), Config, pubsub, user, err) {
  users.insert_session_token(user:, hashed_token:)
}

pub fn delete_user_token(
  hashed_token hashed_token: String,
) -> App(Result(sql.DeleteUserToken, Nil), Config, pubsub, user, err) {
  users.delete_session_token(hashed_token:)
}
