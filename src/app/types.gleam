import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None}
import mist
import wisp
// import app/monad/app.{type App, type Handler}

pub type Context(config, pubsub, user) {
  Context(
    cfg: config,
    pubsub: pubsub,
    user_client_info: UserClientInfo,
    user: Option(user),
  )
}

pub type UserClientInfo {
  UserClientInfo(
    time_zone: String,
    locale: String,
    default: Bool,
  )
}

pub fn default_user_client_info() -> UserClientInfo {
  UserClientInfo(
    time_zone: "Etc/UTC",
    locale: "en-US",
    default: True,
  )
}

pub type Session {
  Session(
    user_token: Option(String),
    user_client_info: Option(UserClientInfo),
  )
}
