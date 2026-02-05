import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import app/generic/json.{type Transcoders, Transcoders} as _

pub type TextMsg {
  //$ derive json encode decode
  TextMsg(text: String)
}

pub const text_transcoders: Transcoders(TextMsg) =
  Transcoders(
    encode: encode_text_msg,
    decoder: decoder_text_msg,
  )

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
