import gleam/http
import gleam/string
import gleam/list
import gleam/dict
import gleam/option.{type Option}
import gleam/result.{try}
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import gleam/uri.{type Uri}
import fpo/oauth/tokens.{type Token, type Encrypted, type Unencrypted}
import fpo/http/err.{type ErrForClient}

pub type Err = err.Err

pub opaque type Req(t, metadata) {
  Req(
    req: Request(String),
    decoder: Decoder(t),
    metadata: Decoder(metadata),
    authorization: Authorization
  )
}

pub type Authorization {
  NoAuthorization
  Bearer(token: Token(Encrypted))
}

pub type Resp(t, metadata) {
  Resp(
    data: t,
    metadata: metadata,
  )
}

pub type RespFull(t, metadata) {
  RespFull(
    data: t,
    metadata: metadata,
    req: Request(String),
    resp: Response(String),
  )
}

// pub type RemoteData(t) {
//   NotAsked
//   Loading
//   Failure(err: Err)
//   Success(t)
// }

pub fn data(
  resp resp: Resp(t, metadata),
) -> t {
  resp.data
}

pub fn send(
  req req: Req(t, metadata),
  decrypt decrypt: fn(Token(Encrypted)) -> Result(Token(Unencrypted), Nil)
) -> Result(Resp(t, metadata), Err) {
  send_(
    req: req.req,
    authz: req.authorization,
    decoder: req.decoder,
    metadata: req.metadata,
    using: hackney.send,
    to_err: err.HttpErr(err: _, req: req.req |> redact_authz_header),
    to_ok: fn(data, metadata, _req, _resp) { Resp(data:, metadata:) },
    decrypt:,
  )
}

pub fn send_full_with_hackney(
  req req: Req(t, metadata),
  decrypt decrypt: fn(Token(Encrypted)) -> Result(Token(Unencrypted), Nil)
) -> Result(RespFull(t, metadata), Err) {
  send_(
    req: req.req,
    authz: req.authorization,
    decoder: req.decoder,
    metadata: req.metadata,
    using: hackney.send,
    to_err: err.HttpErr(err: _, req: req.req |> redact_authz_header),
    to_ok: fn(data, metadata, req, resp) {
      RespFull(data:, metadata:, req:, resp:)
    },
    decrypt:,
  )
}

const authz_header_key = "authorization"

fn redact_authz_header(
  req req: Request(conn),
) -> Request(conn) {
  case req |> request.get_header(authz_header_key) {
    Ok(_) -> req |> request.set_header(authz_header_key, "<< REDACTED >>")
    Error(Nil) -> req
  }
}

fn send_(
  req req: Request(String),
  authz authz: Authorization,
  using dispatch: fn(Request(String)) -> Result(Response(String), err),
  to_ok to_ok: fn(a, metadata, Request(String), Response(String)) -> b,
  to_err to_err: fn(err) -> ErrForClient(err),
  decoder decoder: Decoder(a),
  metadata metadata: Decoder(metadata),
  decrypt decrypt: fn(Token(Encrypted)) -> Result(Token(Unencrypted), Nil)
) -> Result(b, ErrForClient(err)) {
  let req = req |> authorize(authz:, decrypt:)

  case dispatch(req) {
    Ok(resp) -> {
      let req = req |> redact_authz_header

      case read_status(resp:) {
        Good(..) ->
          case parse(resp: resp, decoder:, metadata:) {
            Error(err) ->
              Error(err.JsonParseErr(err:, req:, resp:))

            Ok(#(x, metadata)) ->
              Ok(to_ok(x, metadata, req, resp))
          }

        Bad(status:, kind: Client) ->
          Error(err.ClientErr(status:, req:, resp:))

        Bad(status:, kind: Server) ->
          Error(err.ServerErr(status:, req:, resp:))

        Redirect(status:, location:, url:, headers:) ->
          Error(err.Redirected(status:, location:, url:, headers:))

        Unknown(status:) ->
          Error(err.UnknownResp(status:, req:, resp:))
      }
    }

    Error(err) ->
      Error(to_err(err))
  }
}

pub fn map(
  req req: Req(a, metadata),
  apply f: fn(a) -> b,
) -> Req(b, metadata) {
  Req(..req, decoder: {
    req.decoder
    |> decode.map(f)
  })
}

type ClientOrServer {
  Client
  Server
}

type Status {
  Unknown(
    status: Int,
  )
  Good(
    status: Int,
  )
  Bad(
    status: Int,
    kind: ClientOrServer,
  )
  Redirect(
    status: Int,
    location: String,
    url: Result(Uri, Nil),
    headers: List(http.Header),
  )
}

fn read_status(
  resp resp: Response(String),
) -> Status {
  case resp.status {
    status if status >= 200 && status <= 299 ->
      Good(status:)

    status if status >= 400 && status <= 499 ->
      Bad(status:, kind: Client)

    status if status >= 500 && status <= 599 ->
      Bad(status:, kind: Server)

    status if status >= 500 && status <= 599 ->
      Bad(status:, kind: Server)

    status ->
      case parse_redirect(resp:) {
        Error(Nil) -> Unknown(status:)
        Ok(redirect) -> redirect
      }
  }
}

fn parse_redirect(
  resp resp: Response(String),
) -> Result(Status, Nil) {
  resp
  |> response.get_header("location")
  |> result.map(fn(location) {

    Redirect(
      status: resp.status,
      location:,
      url: uri.parse(location),
      headers: resp.headers,
    )
  })
}

fn parse(
  resp resp: Response(String),
  decoder decoder: Decoder(t),
  metadata metadata: Decoder(metadata),
) -> Result(#(t, metadata), json.DecodeError) {
  use data <- try(resp.body |> json.parse(decoder))
  use metadata <- try(resp.body |> json.parse(metadata))

  Ok(#(data, metadata))
}

pub fn req(
  base_url base_url: String,
  method method: http.Method,
  headers headers: List(#(String, String)),
  path path: String,
  query_params query_params: List(#(String, String)),
  body body: Option(Json),
  authz authorization: Authorization,
  decoder decoder: Decoder(t),
  metadata metadata: Decoder(metadata),
) -> Req(t, metadata) {
  let assert Ok(req) =
    [base_url, path]
    |> string.join("")
    |> request.to()

  let body =
    body
    |> option.map(json.to_string)
    |> option.unwrap("")

  let headers =
    [
      #("content-type", "application/json"),
      #("accept", "application/json")
    ]
    |> combine_using_latter(headers)

  let req =
    req
    |> set_headers(headers)
    |> request.set_method(method)
    |> request.set_query(query_params)
    |> request.set_body(body)

  Req(req:, decoder:, metadata:, authorization:)
}

fn authorize(
  req req: Request(String),
  authz authz: Authorization,
  decrypt decrypt: fn(Token(Encrypted)) -> Result(Token(Unencrypted), Nil)
) -> Request(String) {
  case authz {
    NoAuthorization ->
      req

    Bearer(token:) -> {
      case decrypt(token) {
        Ok(tokens.Token(token:)) -> {
          req
          |> request.set_header("authorization", "Bearer " <> token)
        }

        Error(Nil) -> {
          req
        }
      }
    }
  }
}

fn set_headers(
  req: request.Request(a),
  headers: List(#(String, String)),
) -> Request(a) {
  headers
  |> list.fold(req, fn(req, header) {
    let #(key, val) = header

    request.set_header(req, key, val)
  })
}

pub fn combine_using_latter(
  former: List(#(String, String)),
  latter: List(#(String, String)),
) -> List(#(String, String)) {
  dict.combine(
    dict.from_list(former),
    dict.from_list(latter),
    with: fn(_former_elem, latter_elem) { latter_elem },
  )
  |> dict.to_list
}
