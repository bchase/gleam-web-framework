import gleam/option.{type Option, None}
import app/types.{type Context, type Session, Context}

pub fn build(
  session session: Result(Session, Nil),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  authenticate authenticate: fn(Session, config) -> Option(user),
) -> Context(config, pubsub, user) {
  let #(user, user_client_info) =
    case session {
      Error(Nil) ->
        #(None, None)

      Ok(session) ->
        #(authenticate(session, cfg), session.user_client_info)
    }

  Context(
    cfg:,
    pubsub:,
    user:,
    user_client_info:,
  )
}
