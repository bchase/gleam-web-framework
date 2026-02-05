import app/oauth
import app/oauth/oura
import gleam/option.{type Option, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import gleam/otp/static_supervisor
import app/pubsub
import app/types.{type Session}
import spec/pubsub.{type TextMsg} as _
import spec/user.{type User}

pub fn authenticate(
  session _session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}

pub fn add_pubsub_workers(
  supervisor supervisor: static_supervisor.Builder,
) -> #(static_supervisor.Builder, PubSub) {
  // let #(supervisor, text) =
  //   supervisor
  //   |> pubsub.add_cluster_worker(
  //     name: "text",
  //     app_module_name: spec.app_module_name,
  //     transcoders: pubsub.Transcoders(
  //       encode: config.encode_text_msg,
  //       decoder: config.decoder_text_msg,
  //     )
  //   )

  let #(supervisor, text) = supervisor |> pubsub.add_local_node_only_worker(name: "text")

  let pubsub = PubSub(text:)

  #(supervisor, pubsub)
}

pub type Config {
  Config(
    oura_oauth: oauth.Config,
  )
}

pub type PubSub {
  PubSub(
    text: pubsub.PubSub(TextMsg),
  )
}

// fn empty_pubsub() -> PubSub {
//   PubSub(
//     text: pubsub.zero(),
//   )
// }

pub fn init_config() -> Config {
  let oura_oauth = oura.build_config()

  Config(
    oura_oauth:,
  )
}
