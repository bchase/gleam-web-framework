import gleam/bit_array
import gleam/crypto

pub fn hash_sha256_base64(
  bytes bytes: BitArray,
) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_encode(False)
}
