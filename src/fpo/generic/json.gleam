import birl
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/regexp

pub type Transcoders(t) {
  Transcoders(
    encode: fn(t) -> Json,
    decoder: fn() -> Decoder(t),
  )
}

pub fn decoder_birl_day_from_date_string() -> Decoder(birl.Day) {
  decode.string
  |> decode.then(fn(str) {
    case birl.parse(str <> "T00:00:00Z") {
      Ok(t) -> decode.success(t |> birl.get_day)
      Error(Nil) -> decode.failure(birl.from_unix(0) |> birl.get_day, str)
    }
  })
}

pub fn encode_birl_day_to_date_string_json(
  day day: birl.Day,
) -> Json {
  let assert Ok(trailing_z_re) =
    "[Z]$" |> regexp.from_string

  birl.unix_epoch
  |> birl.set_day(day)
  |> birl.to_date_string
  |> regexp.replace(each: trailing_z_re, in: _, with: "")
  |> json.string
}
