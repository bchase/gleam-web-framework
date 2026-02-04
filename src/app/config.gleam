import app/oauth
import app/oauth/oura
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import app/pubsub2 as pubsub

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

pub fn init() -> Config {
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
