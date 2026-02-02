import gleam/list
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
import app/types.{type Context, type Session}
import app/config.{type Config}
import app/context
import app/websockets
import app/web/session
import app/router
import wisp

// TODO mv
type User {
  User
}
fn authenticate(
  session session: Session,
  cfg _cfg: Config,
) -> Option(User) {
  None
}
// TODO mv

const web_req_handler_worker_shutdown_ms = 60_000

const spec =
  Spec(
    dot_env_relative_path: ".env",
    secret_key_base_env_var_name: "SECRET_KEY_BASE",
    init_config: config.init,
    authenticate:,
    mist_websockets_handler: websockets.handler,
    wisp_handler: router.handler,
  )

pub fn main() -> Nil {
  let assert Ok(_) =
    start_supervisor(spec:, one_for_one_children: [])

  process.sleep_forever()
}

type Spec(config, user) {
  Spec(
    dot_env_relative_path: String,
    secret_key_base_env_var_name: String,
    init_config: fn() -> config,
    authenticate: fn(Session, config) -> Option(user),
    mist_websockets_handler: fn(Request(mist.Connection), Context(config, user)) -> Response(mist.ResponseData),
    wisp_handler: fn(Request(wisp.Connection), Context(config, user)) -> Response(wisp.Body),
  )
}

fn start_supervisor(
  spec spec: Spec(config, user),
  one_for_one_children children: List(fn(config) -> ChildSpecification(Supervisor)),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  load_dot_env(spec.dot_env_relative_path)

  let cfg = spec.init_config()

  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(web_req_handler_worker(cfg:, spec:))
  |> list.fold(children, _, fn(supervisor, child) {
    supervisor
    |> static_supervisor.add(child(cfg))
  })
  |> static_supervisor.start
}

fn web_req_handler_worker(
  cfg cfg: config,
  spec spec: Spec(config, user),
) -> ChildSpecification(Supervisor) {
  supervision.ChildSpecification(
    start: fn() { web_req_handler(cfg:, spec:) },
    restart: supervision.Permanent,
    significant: False,
    child_type: supervision.Worker(shutdown_ms: web_req_handler_worker_shutdown_ms),
  )
}

fn web_req_handler(
  cfg cfg: config,
  spec spec: Spec(config, user),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let Spec(
    secret_key_base_env_var_name:,
    authenticate:,
    mist_websockets_handler:,
    wisp_handler:,
    ..
  ) = spec

  let secret_key_base =
    secret_key_base_env_var_name
    |> secret_key_base(env_var_name: _)

  let wisp_mist_handler =
    wisp_handler
    |> to_mist(secret_key_base:)

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

fn to_mist(
  wisp_handler wisp_handler: fn(Request(wisp.Connection), Context(config, user)) -> Response(wisp.Body),
  secret_key_base secret_key_base: String,
) -> fn(Request(mist.Connection), Context(config, user)) -> Response(mist.ResponseData) {
  fn(mist_req, ctx) {
    fn(wisp_req) {
      use wisp_req <- middleware(wisp_req, static_directory())
      wisp_handler(wisp_req, ctx)
    }
    |> wisp_mist.handler(secret_key_base)
    |> fn(handle_mist) { handle_mist(mist_req) }
  }
}

fn build_web_req_handler(
  mist_req mist_req: Request(mist.Connection),
  cfg cfg: config,
  secret_key_base secret_key_base: String,
  authenticate authenticate: fn(Session, config) -> Option(user),
  mist_websockets_handler mist_websockets_handler: fn(Request(mist.Connection), Context(config, user)) -> Response(ResponseData),
  wisp_mist_handler wisp_mist_handler: fn(Request(mist.Connection), Context(config, user)) -> Response(ResponseData),
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

fn secret_key_base(
  env_var_name env_var_name: String,
) -> String {
  let assert Ok(str) = env.get_string(env_var_name)
  str
}

fn load_dot_env(
  relative_path relative_path: String,
) -> Nil {
  dot_env.new()
  |> dot_env.set_path(relative_path)
  |> dot_env.set_debug(False)
  |> dot_env.load
}

fn static_directory() {
  let assert Ok(priv_directory) = wisp.priv_directory("kohort")
  priv_directory <> "/static"
}
