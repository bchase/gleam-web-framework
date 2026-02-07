import app/cloak.{type Cloak}
import cloak_wrapper/aes/gcm as aes_gcm
import deriv/util as deriv
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None}

pub type Context(config, pubsub, user) {
  Context(
    cfg: config,
    pubsub: pubsub,
    user_client_info: UserClientInfo,
    user: Option(user),
  )
}

pub type Features {
  Features(
    cloak: Option(fn(EnvVar) -> aes_gcm.Config),
  )
}

pub type Flags {
  Flags(
    cloak: Option(Cloak),
  )
}

pub type EnvVar {
  EnvVar(
    get_string: fn(String) -> Result(String, String),
  )
}

pub type Session {
  //$ derive json encode decode
  //$ derive zero
  Session(
    user_token: Option(String),
    user_client_info: Option(UserClientInfo),
  )
}

pub type UserClientInfo {
  //$ derive json encode decode
  UserClientInfo(
    time_zone: String,
    locale: String,
  )
}

pub const default_user_client_info =
  UserClientInfo(
    time_zone: "Etc/UTC",
    locale: "en-US",
  )

// DERIVED

pub fn encode_user_client_info(value: UserClientInfo) -> Json {
  case value {
    UserClientInfo(..) as value ->
      json.object([
        #("locale", json.string(value.locale)),
        #("time_zone", json.string(value.time_zone)),
      ])
  }
}

pub fn decoder_user_client_info() -> Decoder(UserClientInfo) {
  decode.one_of(decoder_user_client_info_user_client_info(), [])
}

pub fn decoder_user_client_info_user_client_info() -> Decoder(UserClientInfo) {
  use time_zone <- decode.field("time_zone", decode.string)
  use locale <- decode.field("locale", decode.string)
  decode.success(UserClientInfo(time_zone:, locale:))
}


pub fn encode_session(value: Session) -> Json {
  case value {
    Session(..) as value ->
      json.object([
        #(
          "user_client_info",
          json.nullable(value.user_client_info, encode_user_client_info),
        ),
        #("user_token", json.nullable(value.user_token, json.string)),
      ])
  }
}

pub fn decoder_session() -> Decoder(Session) {
  decode.one_of(decoder_session_session(), [])
}

pub fn decoder_session_session() -> Decoder(Session) {
  use user_token <- decode.optional_field(
    "user_token",
    deriv.none,
    decode.optional(decode.string),
  )
  use user_client_info <- decode.optional_field(
    "user_client_info",
    deriv.none,
    decode.optional(decoder_user_client_info()),
  )
  decode.success(Session(user_token:, user_client_info:))
}

pub fn zero_session() -> Session {
  Session(None, None)
}
