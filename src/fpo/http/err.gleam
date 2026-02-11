import gleam/http
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/uri.{type Uri}

pub type Err = ErrForClient(hackney.Error)

pub type ErrForClient(err) {
  Redirected(
    status: Int,
    location: String,
    url: Result(Uri, Nil),
    headers: List(http.Header),
  )
  ClientErr(
    status: Int,
    req: Request(String),
    resp: Response(String),
  )
  ServerErr(
    status: Int,
    req: Request(String),
    resp: Response(String),
  )
  UnknownResp(
    status: Int,
    req: Request(String),
    resp: Response(String),
  )
  JsonParseErr(
    err: json.DecodeError,
    req: Request(String),
    resp: Response(String),
  )
  HttpErr(
    err: err,
    req: Request(String),
  )
}
