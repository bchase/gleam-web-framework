import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None}
import mist
import wisp

pub type Spec(config, user) {
  Spec(
    dot_env_relative_path: String,
    secret_key_base_env_var_name: String,
    init_config: fn() -> config,
    authenticate: fn(Session, config) -> Option(user),
    mist_websockets_handler: fn(Request(mist.Connection), Context(config, user)) -> Response(mist.ResponseData),
    wisp_handler: fn(Request(wisp.Connection), Context(config, user)) -> Response(wisp.Body),
  )
}

pub type Context(config, user) {
  Context(
    cfg: config,
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
