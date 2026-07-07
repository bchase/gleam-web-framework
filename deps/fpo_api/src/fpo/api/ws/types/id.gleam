import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Id(resource) {
  Id(id: String)
}

pub fn to_string(
  id id: Id(resource),
) -> String {
  id.id
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

pub fn decoder_id_phantom(
  _
) -> Decoder(Id(resource)) {
  decode.string
  |> decode.map(Id)
}

pub fn encode_id_phantom(
  value value: Id(resource),
  phantom _,
) -> Json {
  json.string(value.id)
}
