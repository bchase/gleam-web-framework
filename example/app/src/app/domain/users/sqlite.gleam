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

// DERIVED

pub fn from_authenticate_user_to_user(
  authenticate_user authenticate_user: sql.AuthenticateUser,
) -> User {
  User(id: authenticate_user.id, name: authenticate_user.name)
}
