import gleam/option.{type Option, None}
import fpo/types.{type Context, type Session, Context, Fpo}

pub fn build(
  session session: Result(Session, Nil),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  authenticate authenticate: fn(Session, config) -> Option(user),
  fpo_path_prefix fpo_path_prefix: String,
  fpo_browser_js_path fpo_browser_js_path: String,
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
    fpo: Fpo(
      path_prefix: fpo_path_prefix,
      browser_js_path: fpo_browser_js_path,
    ),
  )
}
