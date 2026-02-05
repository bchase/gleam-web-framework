import app/oauth
import app/oauth/oura
import gleam/option.{type Option, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import gleam/otp/static_supervisor
import app/pubsub2 as pubsub
import app/types.{type Session}
import app/types/spec.{type Spec, Spec}
import app/websockets
import app/router

pub fn spec() -> Spec(Config, PubSub, User) {
  Spec(
    app_module_name: "app",
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    //
    init_config:,
    add_pubsub_workers:,
    //
    authenticate:,
    //
    websockets_path_prefix: "ws",
    websockets_router: websockets.lustre_server_component_router,
    //
    router: router.handler,
  )
}

pub type User {
  User
}

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
    text: pubsub.PubSub(TextMsg)
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

//

pub type TextMsg {
  //$ derive json encode decode
  TextMsg(text: String)
}

pub type NumberMsg {
  //$ derive json encode decode
  NumberMsg(number: Float)
}

// DERIVED

pub fn encode_text_msg(value: TextMsg) -> Json {
  case value {
    TextMsg(..) as value -> json.object([#("text", json.string(value.text))])
  }
}

pub fn decoder_text_msg() -> Decoder(TextMsg) {
  decode.one_of(decoder_text_msg_text_msg(), [])
}

pub fn decoder_text_msg_text_msg() -> Decoder(TextMsg) {
  use text <- decode.field("text", decode.string)
  decode.success(TextMsg(text:))
}

pub fn encode_number_msg(value: NumberMsg) -> Json {
  case value {
    NumberMsg(..) as value ->
      json.object([#("number", json.float(value.number))])
  }
}

pub fn decoder_number_msg() -> Decoder(NumberMsg) {
  decode.one_of(decoder_number_msg_number_msg(), [])
}

pub fn decoder_number_msg_number_msg() -> Decoder(NumberMsg) {
  use number <- decode.field("number", decode.float)
  decode.success(NumberMsg(number:))
}
