import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Id(resource) {
  Id(id: String)
}

pub fn decoder_id(
) -> Decoder(Id(resource)) {
  decode.string
  |> decode.map(Id)
}

pub fn encode_id(
  value value: Id(resource),
) -> Json {
  json.string(value.id)
}
