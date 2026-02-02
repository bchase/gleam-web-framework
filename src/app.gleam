import gleam/otp/actor
import gleam/int
import dot_env/env
import gleam/result
import gleam/uri
import dot_env
import gleam/erlang/process
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist.{type ResponseData}
import wisp/wisp_mist
import app/handlers/oauth as oauth_handler
import app/oauth
import app/oauth/oura
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision.{type ChildSpecification}
import app/types.{type Config, type UserClientInfo}
import app/config
import app/context
import app/websockets
import app/router
import wisp

const web_req_handler_worker_shutdown_ms = 60_000

pub fn main() -> Nil {
  load_dot_env()

  let cfg = config.init()

  let assert Ok(_) = start_supervisor(cfg:)

  process.sleep_forever()
}

fn start_supervisor(
  cfg cfg: Config,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(web_req_handler_worker(cfg:))
  |> static_supervisor.start
}

fn web_req_handler_worker(
  cfg cfg: Config,
) -> ChildSpecification(Supervisor) {
  supervision.ChildSpecification(
    start: fn() { web_req_handler(cfg:) },
    restart: supervision.Permanent,
    significant: False,
    child_type: supervision.Worker(shutdown_ms: web_req_handler_worker_shutdown_ms),
  )
}

fn web_req_handler(
  cfg cfg: Config,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let mist_websockets_handler =
    websockets.handler(req: _, build_context: context.build_mist(req: _, cfg:))

  let wisp_mist_handler =
    router.handler(req: _, build_context: context.build_wisp(req: _, cfg:))
    |> wisp_mist.handler(secret_key_base())

  build_web_req_handler(
    mist_req: _,
    mist_websockets_handler:,
    wisp_mist_handler:,
  )
  |> mist.new()
  |> mist.bind("0.0.0.0")
  |> mist.port(port())
  // |> mist.with_ipv6
  |> mist.start
}

fn build_web_req_handler(
  mist_req mist_req: Request(mist.Connection),
  mist_websockets_handler mist_websockets_handler: fn(Request(mist.Connection)) -> Response(ResponseData),
  wisp_mist_handler wisp_mist_handler: fn(Request(mist.Connection)) -> Response(ResponseData),
) -> Response(ResponseData) {
  case mist_req |> request.path_segments {
    ["/ws", ..] ->
      mist_req |> mist_websockets_handler

    _ ->
      mist_req |> wisp_mist_handler
  }
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

fn load_dot_env() -> Nil {
  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load
}
