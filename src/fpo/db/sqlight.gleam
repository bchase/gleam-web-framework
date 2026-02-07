import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import sqlight

pub fn encode_sqlight_error(
  err err: sqlight.Error,
) -> Dynamic {
  dynamic.properties([
    #("db" |> dynamic.string, "sqlite" |> dynamic.string),
    #("code" |> dynamic.string, err.code |> encode_sqlight_error_code),
    #("message" |> dynamic.string, err.message |> dynamic.string),
    #("offset" |> dynamic.string, err.offset |> dynamic.int),
  ])
}

fn encode_sqlight_error_code(
  err err: sqlight.ErrorCode,
) -> Dynamic {
  err
  |> sqlight.error_code_to_int
  |> dynamic.int
}

//

pub fn decoder_sqlight_error() -> Decoder(sqlight.Error) {
  use db <- decode.field("db", decode.string)
  use <- bool.lazy_guard(db != "sqlite", fn() { fail_sqlight_error(db) })

  use code <- decode.field("code", decoder_sqlight_error_code())
  use message <- decode.field("message", decode.string)
  use offset <- decode.field("offset", decode.int)

  decode.success(sqlight.SqlightError(code:, message:, offset:))
}

fn decoder_sqlight_error_code() -> Decoder(sqlight.ErrorCode) {
  decode.int
  |> decode.map(sqlight.error_code_from_int)
}

//

fn fail_sqlight_error(
  db db: String
) -> Decoder(sqlight.Error) {
  decode.failure(zero_sqlight_error, "db value is not sqlite: " <> db)
}

const zero_sqlight_error = sqlight.SqlightError(sqlight.Abort, "", 0)
