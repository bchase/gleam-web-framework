import app/db/sqlite as db
import app/sql
import app/types.{type Config}
import fpo/monad/app.{type App}
import gleam/list

pub type User {
  //$ derive from app/sql.GetUserBy
  User(
    id: Int,
    name: String,
  )
}

pub fn get(
  hashed_token hashed_token: String,
) -> App(List(User), Config, pubsub, user) {
  sql.get_user_by(hashed_token:)
  |> db.many
  |> app.map(list.map(_, from_get_user_by_to_user))
}

pub fn insert_session_token(
  user user: User,
  hashed_token hashed_token: String,
) -> App(Result(sql.InsertUserToken, Nil), Config, pubsub, user) {
  sql.insert_user_token(hashed_token:, context: "session", user_id: user.id)
  |> db.one
}

pub fn delete_session_token(
  hashed_token hashed_token: String,
) -> App(Result(sql.DeleteUserToken, Nil), Config, pubsub, user) {
  sql.delete_user_token(hashed_token:)
  |> db.one
}

// DERIVED

pub fn from_get_user_by_to_user(get_user_by get_user_by: sql.GetUserBy) -> User {
  User(id: get_user_by.id, name: get_user_by.name)
}
