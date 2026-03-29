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

// pub type IdString(resource) = Id(resource, String)

// pub fn decoder_id_string() -> Decoder(IdString(resource)) {
//   decoder_id(decoder: decode.string)
// }

// pub fn encode_id_string(
//   value value: IdString(resource),
// ) {
//   encode_id(value:, encode: json.string)
// }

// pub type Id(resource, t) {
//   Id(id: t)
// }

// pub fn decoder_id(
//   decoder decoder: Decoder(t),
// ) -> Decoder(Id(resource, t)) {
//   decoder
//   |> decode.map(Id)
// }

// pub fn encode_id(
//   value value: Id(resource, t),
//   encode encode: fn(t) -> Json
// ) -> Json {
//   encode(value.id)
// }
