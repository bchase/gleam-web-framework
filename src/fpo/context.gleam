import gleam/option.{type Option, None}
import fpo/types.{type Context, type Features, type Session, Context, Features, Fpo}

pub fn build(
  session session: Result(Session, Nil),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  authenticate authenticate: fn(Session, config) -> Option(user),
  features features: Features,
) -> Context(config, pubsub, user) {
  let #(user, user_client_info) =
    case session {
      Error(Nil) ->
        #(None, None)

      Ok(session) ->
        #(authenticate(session, cfg), session.user_client_info)
    }

  let Features(set_user_client_info:, ..) = features

  Context(
    cfg:,
    pubsub:,
    user:,
    user_client_info:,
    fpo: Fpo(
      set_user_client_info:,
    ),
  )
}
