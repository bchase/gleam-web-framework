import gleam/bool
import gleam/list
import gleam/json
import gleam/bit_array
import gleam/result.{try}
import gleam/option.{type Option, Some, None}
import wisp
import gleam/crypto
import gleam/http
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import app/types.{type Session, type UserClientInfo}

// https://github.com/gleam-wisp/wisp/blob/v1.3.0/src/wisp.gleam#L1798-L1817
pub fn write(
  resp resp: Response(wisp.Body),
  req req: Request(wisp.Connection),
  session session: Session,
  max_age max_age: Option(Int),
  session_cookie_name session_cookie_name: String,
) -> Response(wisp.Body) {
  let http_scheme = case req.scheme, req.host {
    http.Http, "localhost" -> http.Http
    _, _ -> http.Https
  }

  let attrs =
    cookie.Attributes(
      ..cookie.defaults(http_scheme),
      same_site: Some(cookie.Lax),
      max_age: max_age,
    )

  let signed_session_str =
    session
    |> types.encode_session
    |> json.to_string
    |> fn(str) { <<str:utf8>> }
    |> wisp.sign_message(req, _, crypto.Sha512)

  resp
  |> response.set_cookie(session_cookie_name, signed_session_str, attrs)
}

pub fn read_mist(
  req req: Request(t),
  name name: String,
  secret_key_base secret_key_base: String,
) -> Result(Session, Nil) {
  use str <- try(read_mist_string(req:, name:, secret_key_base:))
  use session <- try(json.parse(str, types.decoder_session()) |> result.replace_error(Nil))
  Ok(session)
}

fn read_mist_string(
  req req: Request(t),
  name name: String,
  secret_key_base secret_key_base: String,
) -> Result(String, Nil) {
  let cookies = req |> request.get_cookies
  use raw <- try(list.key_find(cookies, name))
  use bits <- try(verify_signed_message(raw, secret_key_base))
  use val <- try(bit_array.to_string(bits))
  Ok(val)
}

// https://github.com/gleam-wisp/wisp/blob/v1.3.0/src/wisp.gleam#L1757C1-L1763C1
fn verify_signed_message(
  message: String,
  secret_key_base: String,
) -> Result(BitArray, Nil) {
  crypto.verify_signed_message(message, <<secret_key_base:utf8>>)
}

//

pub fn set_session_user_client_info_using_req_json_body(
  req req: Request(wisp.Connection),
  session_cookie_name session_cookie_name: String,
) -> Result(Response(wisp.Body), Nil) {
  use uci <- try(read_user_client_info_from_json_body(req:))

  let session =
    read_wisp(req:, name: session_cookie_name)
    |> result.lazy_unwrap(fn() { types.zero_session() })

  let session = types.Session(..session, user_client_info: Some(uci))

  wisp.response(200)
  |> write(req:, session:, max_age: None, session_cookie_name:)
  |> Ok
}

fn read_user_client_info_from_json_body(
  req req: Request(wisp.Connection),
) -> Result(UserClientInfo, Nil) {
  use content_type <- try(req |> request.get_header("content-type"))
  use <- bool.guard(content_type != "application/json", Error(Nil))
  use body <- try(req |> wisp.read_body_bits)
  use body <- try(body |> bit_array.to_string)
  use uci <- try(json.parse(body, types.decoder_user_client_info()) |> result.replace_error(Nil))
  Ok(uci)
}

pub fn read_wisp(
  req req: Request(wisp.Connection),
  name name: String,
) -> Result(Session, Nil) {
  use str <- try(read_string_wisp(req:, name:))
  use session <- try(json.parse(str, types.decoder_session()) |> result.replace_error(Nil))
  Ok(session)
}

fn read_string_wisp(
  req req: Request(wisp.Connection),
  name name: String,
) -> Result(String, Nil) {
  let cookies = req |> request.get_cookies
  use raw <- try(list.key_find(cookies, name))
  use bits <- try(wisp.verify_signed_message(req, raw))
  use val <- try(bit_array.to_string(bits))
  Ok(val)
}
