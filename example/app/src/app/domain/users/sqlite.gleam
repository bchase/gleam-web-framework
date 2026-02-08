import fpo/db/parrot
import app/db/sqlite as db
import app/sql
import app/types.{type Config}
import fpo/monad/app.{type App}
import gleam/list

pub type User {
  //$ derive from app/sql.AuthenticateUser
  User(
    id: Int,
    name: String,
  )
}

pub fn get(
  hashed_token hashed_token: String,
) -> App(List(User), Config, pubsub, user) {
  sql.authenticate_user(hashed_token:)
  |> db.many
  |> app.map(list.map(_, from_authenticate_user_to_user))
}

pub fn insert_session_token(
  user user: User,
  hashed_token hashed_token: String,
) -> App(Result(sql.InsertUserToken, Nil), Config, pubsub, user) {
  sql.insert_user_token(hashed_token:, context: "session", user_id: user.id)
  |> db.one
}

pub fn list_user_tokens(
) -> App(List(sql.ListUserTokens), Config, pubsub, user) {
  sql.list_user_tokens()
  |> db.many
}


pub fn delete_session_token(
  hashed_token hashed_token: String,
) -> App(Result(Nil, Nil), Config, pubsub, user) {
  sql.delete_user_token(hashed_token:)
  |> parrot.from_exec
  |> db.one
}

// DERIVED

pub fn from_authenticate_user_to_user(
  authenticate_user authenticate_user: sql.AuthenticateUser,
) -> User {
  User(id: authenticate_user.id, name: authenticate_user.name)
}
