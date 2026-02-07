import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Transcoders(t) {
  Transcoders(
    encode: fn(t) -> Json,
    decoder: fn() -> Decoder(t),
  )
}
