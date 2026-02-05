import gleam/option.{type Option}
import app/types.{type Context, type Session, Context}

pub fn build(
  session session: Session,
  cfg cfg: config,
  pubsub pubsub: pubsub,
  authenticate authenticate: fn(Session, config) -> Option(user),
) -> Context(config, pubsub, user) {
  let user = authenticate(session, cfg)

  let user_client_info =
    session.user_client_info
    |> option.lazy_unwrap(types.default_user_client_info)

  Context(
    cfg:,
    pubsub:,
    user:,
    user_client_info:,
  )
}
