import gleeunit
import gleeunit/should
import sqlight
import fpo/db/sqlight as app_sqlight
import gleam/crypto
import gleam/json
import gleam/dynamic/decode
import cloak_wrapper/crypto/key
import fpo/generic/crypto as fpo_crypto
import fpo/generic/json.{Transcoders} as _

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn sqlight_err_serialization_test() {
  let message = "sqlight_err_serialization_test"
  let offset = 1234
  let err = sqlight.SqlightError(code: sqlight.Abort, message:, offset:)

  let dyn = err |> app_sqlight.encode_sqlight_error

  dyn
  |> decode.run(app_sqlight.decoder_sqlight_error())
  |> should.be_ok
  |> should.equal(err)
}

const plaintext = "Fear is the little-death that brings total obliteration."

pub fn signed_msg_test() {
  let key = key.gen(32)

  let transcoders = Transcoders(encode: json.string, decoder: fn() { decode.string })

  let msg = fpo_crypto.sign(msg: plaintext, transcoders:, key:, algo: crypto.Sha512)

  msg
  |> should.not_equal(plaintext)

  msg
  |> fpo_crypto.verify(transcoders:, key:)
  |> should.be_ok
  |> should.equal(plaintext)
}
