import gleam/dict.{type Dict}
import gleam/bit_array
import gleam/result.{try}
import gleam/option.{type Option, Some, None}
import wisp
import gleam/crypto
import gleam/http
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import app/types.{type Session, Session, type UserClientInfo, UserClientInfo}

const session_cookie_name = "kohort"
const time_zone_cookie_name = "kohort.tz"
const locale_cookie_name = "kohort.locale"

// https://github.com/gleam-wisp/wisp/blob/v1.3.0/src/wisp.gleam#L1798-L1817
pub fn write_session(
  resp resp: Response(wisp.Body),
  req req: Request(wisp.Connection),
  user_token user_token: Option(String),
  max_age max_age: Option(Int),
) -> Response(wisp.Body) {
  let http_scheme = case req.scheme, req.host {
    http.Http, "localhost" -> http.Http
    _, _ -> http.Https
  }

  let user_token =
    user_token
    |> option.map(fn(str) { <<str:utf8>> })
    |> option.map(wisp.sign_message(req, _, crypto.Sha512))
    |> option.unwrap("")

  let attrs =
    cookie.Attributes(
      ..cookie.defaults(http_scheme),
      same_site: Some(cookie.Lax),
      max_age: max_age,
    )

  resp
  |> response.set_cookie(session_cookie_name, user_token, attrs)
}

pub fn from_mist(
  req req: Request(t),
  secret_key_base secret_key_base: String,
) -> Session {
  let cookies = cookies(req:)

  let user_client_info =
    cookies
    |> build_user_client_info(secret_key_base:)
    |> option.from_result

  case get(cookies:, key: session_cookie_name, secret_key_base:) {
    Ok(user_token) ->
      Session(user_token: Some(user_token), user_client_info:)

    Error(Nil) ->
      Session(user_token: None, user_client_info:)
  }
}

// // based on: https://github.com/gleam-wisp/wisp/blob/v1.3.0/src/wisp.gleam#L1839-L1854
// pub fn from_wisp(
//   req req: Request(wisp.Connection),
// ) -> Session {
//   from_mist(req, req.body.secret_key_base)
// }

fn build_user_client_info(
  cookies cookies: Dict(String, String),
  secret_key_base secret_key_base: String,
) -> Result(UserClientInfo, Nil) {
  use time_zone <- try(
    cookies |> get(key: time_zone_cookie_name, secret_key_base:)
  )

  use locale <- try(
    cookies |> get(key: locale_cookie_name, secret_key_base:)
  )

  Ok(UserClientInfo(time_zone:, locale:, default: False))
}

fn get(
  cookies cookies: Dict(String, String),
  key key: String,
  secret_key_base secret_key_base: String,
) -> Result(String, Nil) {
  // req
  // |> request.get_cookies()
  // |> list.key_find(key)
  // |> result.try(verify_signed_message(_, secret_key_base))
  // |> result.try(bit_array.to_string)
  use raw <- try(dict.get(cookies, key))
  use bits <- try(verify_signed_message(raw, secret_key_base))
  use val <- try(bit_array.to_string(bits))
  Ok(val)
}

fn cookies(
  req req: Request(t),
) -> Dict(String, String) {
  req
  |> request.get_cookies
  |> dict.from_list
}

// https://github.com/gleam-wisp/wisp/blob/v1.3.0/src/wisp.gleam#L1757C1-L1763C1
fn verify_signed_message(
  message: String,
  secret_key_base: String,
) -> Result(BitArray, Nil) {
  crypto.verify_signed_message(message, <<secret_key_base:utf8>>)
}

pub fn set_user_client_info_in_session(
  req: Request(wisp.Connection),
) -> Response(wisp.Body) {
  use form <- wisp.require_form(req)
  let form = form.values |> dict.from_list

  {
    use tz <- try(dict.get(form, "time_zone"))
    use locale <- try(dict.get(form, "locale"))

    wisp.response(200)
    |> wisp.set_cookie(
      req,
      time_zone_cookie_name,
      tz,
      wisp.Signed,
      365 * 24 * 60 * 60,
    )
    |> wisp.set_cookie(
      req,
      locale_cookie_name,
      locale,
      wisp.Signed,
      365 * 24 * 60 * 60,
    )
    |> Ok
  }
  |> result.unwrap(wisp.response(400))
}
