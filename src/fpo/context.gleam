import gleam/erlang/process
import gleam/option.{type Option, None}
import fpo/types.{type Context, type Features, type Session, type SecretKeyBase, Context, Fpo}

pub fn build(
  session session: Result(Session, Nil),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  fpo fpo: types.Fpo,
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

  let fpo =
    Fpo(..fpo,
      path_prefix: features.fpo_path_prefix, // TODO maybe init in `web`
      set_user_client_info: features.set_user_client_info,
    )

  Context(
    cfg:,
    pubsub:,
    user:,
    user_client_info:,
    fpo:,
  )
}

pub fn secret_key_base(
  ctx ctx: Context(config, pubsub, user)
) -> Result(SecretKeyBase, Nil) {
  let subj = process.named_subject(ctx.fpo.secret_key_base)
  let self = process.new_subject()
  process.send(subj, self)
  process.receive(self, 1_000)
}
