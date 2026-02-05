import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}

pub type TextMsg {
  //$ derive json encode decode
  TextMsg(text: String)
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
