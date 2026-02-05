import gleam/dynamic/decode
import gleeunit
import gleeunit/should
import sqlight
import app/db/sqlight as app_sqlight

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

