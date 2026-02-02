import gleam/option.{type Option, Some, None}
import gleam/bool
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
import app/types.{type Context, type Config, type UserClientInfo, type Session}
import app/config
import app/context
import app/websockets
import app/web/session
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
  let secret_key_base = secret_key_base()

  let mist_websockets_handler =
    websockets.handler

  let wisp_mist_handler =
    fn(req, ctx) {
      router.handler(req: _, ctx:)
      |> wisp_mist.handler(secret_key_base)
      |> fn(handle) { handle(req) }
    }

  build_web_req_handler(
    mist_req: _,
    mist_websockets_handler:,
    wisp_mist_handler:,
    cfg:,
    secret_key_base:,
    authenticate:,
  )
  |> mist.new()
  |> mist.bind("0.0.0.0")
  |> mist.port(port())
  // |> mist.with_ipv6
  |> mist.start
}

fn build_web_req_handler(
  mist_req mist_req: Request(mist.Connection),
  mist_websockets_handler mist_websockets_handler: fn(Request(mist.Connection), Context(user)) -> Response(ResponseData),
  wisp_mist_handler wisp_mist_handler: fn(Request(mist.Connection), Context(user)) -> Response(ResponseData),
  cfg cfg: Config,
  secret_key_base secret_key_base: String,
  authenticate authenticate: fn(Session, Config) -> Option(user),
) -> Response(ResponseData) {
let session = session.from_mist(req: mist_req, secret_key_base:)
  let ctx = context.build(session:, cfg:, authenticate:)

  case mist_req |> request.path_segments {
    ["/ws", ..] ->
      mist_req |> mist_websockets_handler(ctx)

    _ ->
      mist_req |> wisp_mist_handler(ctx)
  }
}

type User {
  User
}

fn authenticate(
  session session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}

fn handle_request(
  req req: Request(wisp.Connection),
  cfg cfg: Config,
  handler handle: fn(Request(wisp.Connection), Context(user)) -> Response(wisp.Body),
  authenticate authenticate: fn(Session, Config) -> Option(user),
) -> Response(wisp.Body) {
  let session = session.from_wisp(req:)

  use req <- middleware(req, static_directory())

  let ctx = context.build(session:, cfg:, authenticate:)

  handle(req, ctx)
}

fn middleware(
  req req: wisp.Request,
  static_directory static_directory: String,
  handler handle: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)

  use <- default_responses

  handle(req)
}

fn default_responses(
  handler handle: fn() -> wisp.Response,
) -> wisp.Response {
  let response = handle()

  use <- bool.guard(when: !is_empty(response.body), return: response)

  case response.status {
    404 | 405 ->
      "<h1>Not found</h1>"
      |> wisp.html_body(response, _)

    400 | 422 ->
      "<h1>Bad request</h1>"
      |> wisp.html_body(response, _)

    413 ->
      "<h1>Request entity too large</h1>"
      |> wisp.html_body(response, _)

    500 ->
      "<h1>Internal server error</h1>"
      |> wisp.html_body(response, _)

    _ -> response
  }
}

fn is_empty(
  body body: wisp.Body,
) -> Bool {
  case body {
    wisp.Text("") -> True
    wisp.Bytes(bytes) -> bytes == bytes_tree.new()
    _ -> False
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

fn static_directory() {
  let assert Ok(priv_directory) = wisp.priv_directory("kohort")
  priv_directory <> "/static"
}
