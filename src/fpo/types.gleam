import cloak_wrapper/aes/gcm as aes_gcm
import deriv/util as deriv
import fpo/cloak.{type Cloak}
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/process
import gleam/json.{type Json}
import gleam/option.{type Option, None}
import pog

pub type Context(config, pubsub, user) {
  Context(
    cfg: config,
    pubsub: pubsub,
    user_client_info: Option(UserClientInfo),
    user: Option(user),
    fpo: Fpo,
  )
}

pub type SecretKeyBase {
  SecretKeyBase(BitArray)
}

pub type Fpo {
  Fpo(
    secret_key_base: process.Name(process.Subject(SecretKeyBase)),
    path_prefix: String,
    set_user_client_info: Option(SetUserClientInfo),
  )
}
pub type SetUserClientInfo {
  SetUserClientInfo(
    path_prefix: String, // TODO rm now that in `Fpo`
    browser_js_path: String,
  )
}

pub type Features {
  Features(
    fpo_path_prefix: String,
    cloak: Option(fn(EnvVar) -> aes_gcm.Config),
    set_user_client_info: Option(SetUserClientInfo),
    pog: Option(Pog)
  )
}

pub type Pog {
  PogConnUrlEnvVar(name: String)
  Pog(conn_url: String)
}

pub type Flags {
  Flags(
    cloak: Option(Cloak),
    pog: Option(pog.Connection),
    env_var: EnvVar,
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
    kv: Dict(String, String),
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

// TODO fix `deriv` to use `dict.new()`
fn zero_dict() -> Dict(a, b) { dict.new() }

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
        #("kv", json.dict(value.kv, fn(str) { str }, json.string)),
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
  use kv <- decode.field("kv", decode.dict(decode.string, decode.string))
  decode.success(Session(user_token:, user_client_info:, kv:))
}

pub fn zero_session() -> Session {
  Session(None, None, zero_dict())
}
