import gleam/option.{type Option}
import app/types.{type Config, type Context, type Session, Context}

pub fn build(
  session session: Session,
  cfg cfg: Config,
  authenticate authenticate: fn(Session, Config) -> Option(user),
) -> Context(user) {
  let user = authenticate(session, cfg)

  let user_client_info =
    session.user_client_info
    |> option.lazy_unwrap(types.default_user_client_info)

  Context(
    cfg:,
    user:,
    user_client_info:,
  )
}
