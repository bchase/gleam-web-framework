import tempo/time
import gtz
import tempo/datetime
import gleam/option.{type Option, Some, None}
import gleam/int
import birl
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
import fpo/generic/birl as fbirl
import tempo
import fpo/generic/tempo as ftempo

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

pub fn tempo_test() {
  // let assert Ok(ny) = gtz.timezone("America/New_York")

  // let assert Ok(jst) = datetime.from_string("2026-02-24T11:33:10+09:00")
  // let assert Ok(est) = datetime.from_string("2026-02-23T21:33:10-05:00")

  // jst
  // |> datetime.to_timezone(ny)
  // |> datetime.to_string
  // |> should.equal(est |> datetime.to_string)

  let assert Ok(jst) = datetime.from_string("2025-08-28T11:33:10+09:00")
  // let assert Ok(edt) = datetime.from_string("2025-08-27T22:33:10-04:00")

  // jst
  // |> datetime.to_timezone(ny)
  // |> datetime.to_string
  // |> should.equal(edt |> datetime.to_string)

  jst
  |> ftempo.start_of_day
  |> datetime.to_string
  |> should.equal("2025-08-28T00:00:00.000000+09:00")

  jst
  |> ftempo.end_of_day
  |> datetime.to_string
  |> should.equal("2025-08-28T23:59:59.999999+09:00")

  jst
  |> ftempo.end_of_day_instant_24
  |> datetime.to_string
  |> should.equal("2025-08-28T24:00:00.000000+09:00")
}

// pub fn birl_offset_minutes_test() {
//   // let assert Ok(t1_utc) = birl.parse("2026-02-23T08:23:23Z")
//   let assert Ok(t1_edt) = birl.parse("2026-02-23T03:23:23-05:00")

//   t1_edt
//   |> fbirl.offset_minutes
//   |> should.equal(-300)
// }

// pub fn convert_tz_test() {
//   let assert Ok(jst) = birl.parse("2026-02-24T11:33:10+09:00")
//   let assert Ok(est) = birl.parse("2026-02-23T21:33:10-05:00")

//   let assert Ok(tz) = fbirl.parse_timezone("America/New_York")

//   jst |> birl.to_iso8601 |> should.not_equal(est |> birl.to_iso8601)
//   jst |> fbirl.convert(tz) |> birl.to_iso8601 |> should.equal(est |> birl.to_iso8601)

//   // let assert Ok(t1_utc) = birl.parse("2026-02-23T08:23:23Z")      // UTC
//   // let assert Ok(t1_edt) = birl.parse("2026-02-23T03:23:23-05:00") // EDT (DST)

//   // birl.to_unix_milli(t1_utc) |> should.equal(birl.to_unix_milli(t1_edt))

//   // let t1_utc_bod = t1_utc |> fbirl.beginning_of_day
//   // let t1_utc_eod = t1_utc |> fbirl.end_of_day
//   // let t1_edt_bod = t1_edt |> fbirl.beginning_of_day
//   // let t1_edt_eod = t1_edt |> fbirl.end_of_day

//   // t1_utc_bod |> birl.to_iso8601 |> should.equal("2026-02-23T00:00:00.000Z")
//   // t1_utc_eod |> birl.to_iso8601 |> should.equal("2026-02-23T23:59:59.999Z")
//   // t1_edt_bod |> birl.to_iso8601 |> should.equal("2026-02-23T00:00:00.000-05:00")
//   // t1_edt_eod |> birl.to_iso8601 |> should.equal("2026-02-23T23:59:59.999-05:00")

//   // t1_utc_bod |> should.not_equal(t1_edt_bod)
//   // t1_utc_eod |> should.not_equal(t1_edt_eod)




//   // todo as "test bod/eod after setting timezone on utc time"

//   // let assert Ok(t2_utc) = birl.parse("2025-08-27T08:23:23Z")      // UTC
//   // let assert Ok(t2_est) = birl.parse("2025-08-27T04:23:23-04:00") // EST (not DST)

//   // birl.to_unix_milli(t2_utc)
//   // |> should.equal(birl.to_unix_milli(t2_est))

//   // let assert Ok(tz) = fbirl.parse_timezone("America/New_York")

//   // // t1_utc
//   // // |> fbirl.convert(tz:)
//   // // |> birl.to_iso8601
//   // // |> echo
// }
