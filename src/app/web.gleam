import gleam/string
import lustre/element/html
import gleam/string_tree
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/bool
import gleam/otp/actor
import gleam/int
import dot_env/env
import gleam/result
import dot_env
import gleam/http/response as resp
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist
import wisp/wisp_mist
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision.{type ChildSpecification}
import app/types.{type Spec, type Context, type Session, Spec}
import app/context
import app/web/session
import app/monad/app.{type App}
import app/types/err.{type Err}
import wisp
import lustre/element.{type Element}

const web_req_handler_worker_shutdown_ms = 60_000

pub type Handler(config, user) {
  MistHandler(handle: fn(Request(mist.Connection), Context(config, user)) -> resp.Response(mist.ResponseData))
  WispHandler(handle: fn(Request(wisp.Connection), Context(config, user)) -> resp.Response(wisp.Body))
  AppWispHandler(handle: fn(Request(wisp.Connection)) -> App(resp.Response(wisp.Body), config, user))
  AppMistHandler(handle: fn(Request(mist.Connection)) -> App(resp.Response(mist.ResponseData), config, user))
  AppLustreHandler(handle: fn(Request(wisp.Connection)) -> App(LustreResponse, config, user))
}

pub type LustreResponse {
  LustreResponse(
    status: Int,
    headers: Dict(String, String),
    element: Element(Nil),
  )
}

pub fn run(
  req req: Request(mist.Connection),
  handler handler: Handler(config, user),
  ctx ctx: Context(config, user),
  secret_key_base secret_key_base: String,
) -> resp.Response(mist.ResponseData) {
  case handler {
    MistHandler(handle:) ->
      req
      |> handle(ctx)

    WispHandler(handle:) ->
      req
      |> wisp_mist.handler(handle(_, ctx), secret_key_base)

    AppMistHandler(handle:) ->
      req
      |> handle
      |> app.run(ctx)
      |> fn(result) {
        case result {
          Error(err) -> err |> to_err_resp
          Ok(resp) -> resp
        }
      }

    AppWispHandler(handle:) ->
      req
      |> run_app_handle(handle:, ctx:, secret_key_base:, map_ok: fn(resp) {
        resp
      })

    AppLustreHandler(handle:) ->
      req
      |> run_app_handle(handle:, ctx:, secret_key_base:, map_ok: fn(resp) {
        let LustreResponse(status:, headers:, element:) = resp
        wisp_html_resp(status:, headers:, element:)
      })
  }
}

fn run_app_handle(
  req req: Request(mist.Connection),
  handle handle: fn(Request(wisp.Connection)) -> App(t, config, user),
  map_ok f: fn(t) -> resp.Response(wisp.Body),
  ctx ctx: Context(config, user),
  secret_key_base secret_key_base: String,
) -> resp.Response(mist.ResponseData) {
  req
  |> wisp_mist.handler(fn(req) {
    req
    |> handle
    |> app.run(ctx)
    |> fn(result) {
      case result {
        Ok(x) -> f(x)
        Error(err) -> err |> to_wisp_err_resp
      }
    }
  }, secret_key_base)
}

fn to_wisp_err_resp(
  err err: Err,
) -> resp.Response(wisp.Body) {
  case err {
    err.NotFound(..) ->
      wisp_html_resp(
        status: 404,
        element: html.text("Not Found"),
        headers: dict.new(),
      )

    err.Err(..) ->
      wisp_html_resp(
        status: 500,
        element: html.text("Internal Server Error"),
        headers: dict.new(),
      )
  }
}

fn to_err_resp(
  err err: Err,
) -> resp.Response(mist.ResponseData) {
  case err {
    err.NotFound(..) ->
      mist_html_resp(
        status: 404,
        element: html.text("Not Found"),
        headers: dict.new(),
      )

    err.Err(..) ->
      mist_html_resp(
        status: 500,
        element: html.text("Internal Server Error"),
        headers: dict.new(),
      )
  }
}

fn mist_html_resp(
  status status: Int,
  element element: Element(msg),
  headers headers: Dict(String, String),
) -> resp.Response(mist.ResponseData) {
  let body =
    element
    |> element.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

   status
  |> resp.new
  |> resp.set_body(body)
  |> list.fold(headers |> dict.to_list, _, fn(resp, t) {
    let #(key, val) = t
    resp
    |> wisp.set_header(key, val)
  })
  |> wisp.set_header("content-type", "text/html")
}

fn wisp_html_resp(
  status status: Int,
  element element: Element(msg),
  headers headers: Dict(String, String),
) -> resp.Response(wisp.Body) {
  element
  |> element.to_string_tree
  |> string_tree.to_string
  |> wisp.html_response(status)
  |> list.fold(headers |> dict.to_list, _, fn(resp, t) {
    let #(key, val) = t
    resp
    |> wisp.set_header(key, val)
  })
}

pub fn start_supervisor(
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
  wisp_handler wisp_handler: fn(Request(wisp.Connection), Context(config, user)) -> resp.Response(wisp.Body),
  secret_key_base secret_key_base: String,
) -> fn(Request(mist.Connection), Context(config, user)) -> resp.Response(mist.ResponseData) {
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
  mist_websockets_handler mist_websockets_handler: fn(Request(mist.Connection), Context(config, user)) -> resp.Response(mist.ResponseData),
  wisp_mist_handler wisp_mist_handler: fn(Request(mist.Connection), Context(config, user)) -> resp.Response(mist.ResponseData),
) -> resp.Response(mist.ResponseData) {
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
