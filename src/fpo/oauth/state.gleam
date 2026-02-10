import gleam/bool
import gleam/order
import birl.{type Time}
import birl/duration
import deriv/util.{decoder_birl_parse, encode_birl_to_iso8601}
import fpo/generic/json.{Transcoders} as _
import fpo/monad/app.{type App, pure}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub const transcoders = Transcoders(encode_state, decoder_state)

pub type State {
  //$ derive json encode decode
  State(
    expires_at: Time,
    //$ json decoder decoder_birl_parse
    //$ json encode encode_birl_to_iso8601
  )
}

pub fn new_signed(
) -> App(String, config, pubsub, user, err) {
  birl.utc_now()
  |> birl.add(duration.minutes(15))
  |> State(expires_at: _)
  |> app.sign(msg: _, transcoders:)
}

pub fn verify(
  msg msg: String,
) -> App(Result(State, Nil), config, pubsub, user, err) {
  use state <- app.do__(app.verify(msg:, transcoders:), Nil)

  let expired = birl.compare(state.expires_at, birl.utc_now()) == order.Gt

  use <- bool.guard(expired, pure(Error(Nil)))

  pure(Ok(state))
}

// DERIVED

pub fn encode_state(value: State) -> Json {
  case value {
    State(..) as value ->
      json.object([#("expires_at", encode_birl_to_iso8601(value.expires_at))])
  }
}

pub fn decoder_state() -> Decoder(State) {
  decode.one_of(decoder_state_state(), [])
}

pub fn decoder_state_state() -> Decoder(State) {
  use expires_at <- decode.field("expires_at", decoder_birl_parse())
  decode.success(State(expires_at:))
}
