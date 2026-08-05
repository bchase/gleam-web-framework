import bchase/json.{Transcoder} as _
import bchase/web/sse.{type SSE, SSE}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Greeting {
  //$ derive json encode decode
  Greeting(
    msg: String,
  )
}

pub fn example(
) -> SSE(Greeting) {
  SSE(
    path_segments: ["ws", "greetings"],
    json: greeting,
  )
}

const greeting = Transcoder(encode_greeting, decoder_greeting)

// DERIVED

pub fn encode_greeting(value: Greeting) -> Json {
  case value {
    Greeting(..) as value -> json.object([#("msg", json.string(value.msg))])
  }
}

pub fn decoder_greeting() -> Decoder(Greeting) {
  decode.one_of(decoder_greeting_greeting(), [])
}

pub fn decoder_greeting_greeting() -> Decoder(Greeting) {
  use msg <- decode.field("msg", decode.string)
  decode.success(Greeting(msg:))
}
