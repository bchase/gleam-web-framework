import gleam/int
import dot_env/env
import gleam/result
import wisp
import gleam/uri
import dot_env
import gleam/erlang/process
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist.{type Connection, type ResponseData}
import wisp/wisp_mist
import app/handlers/oauth as oauth_handler
import app/oauth
import app/oauth/oura

pub fn main() -> Nil {
  load_dot_env()

  let cfg = oura.build_config()

  let wisp_handler = wisp_mist.handler(app_wisp(req: _, cfg:), secret_key_base())
  let mist_handler = app_mist(req: _, cfg:)

  let req_handler = req_handler(mist_req: _, mist_handler:, wisp_handler:)

  let assert Ok(_) =
    req_handler
    |> mist.new()
    |> mist.bind("0.0.0.0")
    |> mist.port(port())
    // |> mist.with_ipv6
    |> mist.start

  process.sleep_forever()
}

fn port() -> Int {
  env.get_string("PORT")
  |> result.replace_error(Nil)
  |> result.try(int.parse)
  |> result.unwrap(5000)
}

fn secret_key_base() -> String {
  let assert Ok(str) = env.get_string("SECRET_KEY_BASE")
  str
}

fn req_handler(
  mist_req mist_req: Request(Connection),
  mist_handler mist_handler: fn(Request(Connection)) -> Response(ResponseData),
  wisp_handler wisp_handler: fn(Request(Connection)) -> Response(ResponseData),
) -> Response(ResponseData) {
  case mist_req |> request.path_segments {
    ["/ws", ..] ->
      mist_req |> mist_handler

    _ ->
      mist_req |> wisp_handler
  }
}

fn app_wisp(
  req req: Request(wisp.Connection),
  cfg cfg: oauth.Config,
) -> Response(wisp.Body) {
  case req |> wisp.path_segments {
    _ ->
      ""
      |> wisp.html_response(200)
  }
}

fn app_mist(
  req req: Request(Connection),
  cfg cfg: oauth.Config,
) -> Response(ResponseData) {
  case req |> request.path_segments {
    [] ->
      200
      |> response.new
      |> response.set_body({
        "hi"
        |> bytes_tree.from_string
        |> mist.Bytes
      })

    ["auth", "oura"] -> {
      // let url = uri.to_string(oauth.authorize_redirect_uri(cfg))
      let url = todo

      301
      |> response.new
      |> response.set_header("location", url)
      |> response.set_body(
        bytes_tree.new()
        |> mist.Bytes
      )
    }

    _ ->
      404
      |> response.new
      |> response.set_body({
        "not found"
        |> bytes_tree.from_string
        |> mist.Bytes
      })
  }
}

fn load_dot_env() -> Nil {
  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load
}
