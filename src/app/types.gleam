import gleam/option.{type Option, None}
import app/oauth

pub type Config {
  Config(
    oura_oauth: oauth.Config,
  )
}

pub type Context = ContextWith(Nil)

pub type ContextWith(user) {
  Context(
    cfg: Config,
    user_client_info: UserClientInfo,
    user: Option(user),
  )
}

pub fn context_without_user_or_client_info(
  cfg cfg: Config,
) -> ContextWith(user) {
  Context(
    cfg:,
    user_client_info: default_user_client_info(),
    user: None,
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
