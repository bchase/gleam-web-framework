import gleam/option.{type Option}
import app/cloak.{type Cloak}
import cloak_wrapper/aes/gcm as aes_gcm

pub type Context(config, pubsub, user) {
  Context(
    cfg: config,
    pubsub: pubsub,
    user_client_info: UserClientInfo,
    user: Option(user),
  )
}

pub type Features {
  Features(
    cloak: Option(fn(EnvVar) -> aes_gcm.Config),
  )
}

pub type Flags {
  Flags(
    cloak: Option(Cloak),
  )
}

pub type EnvVar {
  EnvVar(
    get_string: fn(String) -> Result(String, String),
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
    get_session_cookie: fn(String) -> Result(String, Nil)
  )
}
