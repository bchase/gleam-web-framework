import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/result.{try}
import fpo/generic/json.{type Transcoders} as _

pub fn hash_sha256_base64(
  bytes bytes: BitArray,
) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_encode(False)
}

pub fn sign(
  msg msg: t,
  transcoders transcoders: Transcoders(t),
  key key: BitArray,
  algo algo: crypto.HashAlgorithm,
) -> String {
  msg
  |> transcoders.encode
  |> json.to_string
  |> bit_array.from_string
  |> crypto.sign_message(key, algo)
}

pub fn verify(
  msg msg: String,
  transcoders transcoders: Transcoders(t),
  key key: BitArray,
) -> Result(t, Nil) {
  use bytes <- try(crypto.verify_signed_message(msg, key))
  use str <- try(bit_array.to_string(bytes))
  use state <- try(json.parse(str, transcoders.decoder()) |> result.replace_error(Nil))
  Ok(state)
}
