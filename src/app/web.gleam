import lustre/element/html
import gleam/string_tree
import gleam/dict.{type Dict}
import gleam/list
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
import app/types.{type Context, type EnvVar, EnvVar}
import app/context
import app/web/session
import app/monad/app.{type App}
import app/types/err.{type Err}
import app/types/spec.{type Spec, type Handler, WispHandler, AppWispHandler, AppWispSessionCookieHandler, AppLustreHandler, LustreResponse}
import lustre/element.{type Element}
import wisp
import app/flags

const web_req_handler_worker_shutdown_ms = 60_000

pub fn supervised(
  spec spec: Spec(config, pubsub, user),
) -> static_supervisor.Builder {
  let #(supervisor, _, _) = init(spec:)
  supervisor
}

pub fn init(
  spec spec: Spec(config, pubsub, user),
) -> #(static_supervisor.Builder, config, pubsub) {
  let env_var = load_dot_env(spec.dot_env_relative_path)

  let #(supervisor, pubsub) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> spec.add_pubsub_workers

  let #(add_worker_funcs, flags) =
    flags.build(features: spec.config.features, env_var:)

  let supervisor =
    supervisor
    |> list.fold(add_worker_funcs, _, fn(supervisor, add_worker) {
      supervisor |> add_worker
    })

  let cfg = spec.config.init(flags)

  let supervisor =
    supervisor
    |> static_supervisor.add(web_req_handler_worker(cfg:, spec:, pubsub:))

  #(supervisor, cfg, pubsub)
}

fn web_req_handler_worker(
  cfg cfg: config,
  pubsub pubsub: pubsub,
  spec spec: Spec(config, pubsub, user),
) -> ChildSpecification(Supervisor) {
  supervision.ChildSpecification(
    start: fn() { web_req_handler(cfg:, spec:, pubsub:) },
    restart: supervision.Permanent,
    significant: False,
    child_type: supervision.Worker(shutdown_ms: web_req_handler_worker_shutdown_ms),
  )
}

fn web_req_handler(
  cfg cfg: config,
  pubsub pubsub: pubsub,
  spec spec: Spec(config, pubsub, user),
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let app_module_name = spec.app_module_name
  let session_cookie_name = spec.session_cookie_name

  let secret_key_base =
    spec.secret_key_base_env_var_name
    |> secret_key_base(env_var_name: _)

  let handle_wisp_mist =
    fn(req: Request(wisp.Connection), ctx: Context(config, pubsub, user)) -> resp.Response(wisp.Body) {
      case spec.router(req, ctx) {
        Error(Nil) ->
          Error(Nil)

        Ok(handler) ->
          Ok(run_handler(req:, handler:, ctx:, session_cookie_name:))
      }
      |> fn(result) {
        case result {
          Error(Nil) ->
            req |> default_wisp_response

          Ok(resp) ->
            resp
        }
      }
    }
    |> to_mist(secret_key_base:, app_module_name:)

  let handle_mist_websockets =
    fn(mist_req: Request(mist.Connection), ctx: Context(config, pubsub, user)) -> resp.Response(mist.ResponseData) {
      mist_req
      |> spec.websockets_router(ctx)
      |> fn(result) {
        case result {
          Ok(resp) -> resp
          Error(Nil) -> mist_req |> default_mist_websockets_response
        }
      }
    }

  build_web_req_handler(
    mist_req: _,
    cfg:,
    pubsub:,
    secret_key_base:,
    spec:,
    handle_wisp_mist:,
    handle_mist_websockets:,
    session_cookie_name:,
  )
  |> mist.new()
  |> mist.bind("0.0.0.0")
  |> mist.port(port())
  // |> mist.with_ipv6
  |> mist.start
}

fn to_mist(
  wisp_handler wisp_handler: fn(Request(wisp.Connection), Context(config, pubsub, user)) -> resp.Response(wisp.Body),
  secret_key_base secret_key_base: String,
  app_module_name app_module_name: String,
) -> fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData) {
  fn(mist_req, ctx) {
    fn(wisp_req) {
      use wisp_req <- middleware(wisp_req, static_directory(app_module_name:))
      wisp_handler(wisp_req, ctx)
    }
    |> wisp_mist.handler(secret_key_base)
    |> fn(handle_mist) { handle_mist(mist_req) }
  }
}

fn run_handler(
  req req: Request(wisp.Connection),
  handler handler: Handler(config, pubsub, user),
  ctx ctx: Context(config, pubsub, user),
  session_cookie_name session_cookie_name: String,
) -> resp.Response(wisp.Body) {
  case handler {
    WispHandler(handle:) ->
      // req
      // |> wisp_mist.handler(handle(_, ctx), secret_key_base)
      req
      |> handle(ctx)

    AppWispHandler(handle:) ->
      // req
      // |> run_app_handle(handle:, ctx:, secret_key_base:, map_ok: fn(resp) {
      //   resp
      // })
      req
      |> run_app_handle_wisp(handle:, ctx:, map_ok: fn(x) { x })

    AppWispSessionCookieHandler(handle:) ->
      // req
      // |> run_app_handle(handle:, ctx:, secret_key_base:, map_ok: fn(resp) {
      //   resp
      // })
      req
      |> run_app_handle_wisp(handle: handle(_, session_cookie_name), ctx:, map_ok: fn(x) { x })

    AppLustreHandler(handle:) ->
      // req
      // |> run_app_handle(handle:, ctx:, secret_key_base:, map_ok: fn(resp) {
      //   let LustreResponse(status:, headers:, element:) = resp
      //   wisp_html_resp(status:, headers:, element:)
      // })
      req
      |> run_app_handle_wisp(handle:, ctx:, map_ok: fn(resp) {
        let LustreResponse(status:, headers:, element:) = resp
        wisp_html_resp(status:, headers:, element:)
      })

//     MistHandler(handle:) ->
//       req
//       |> handle(ctx)

//     AppMistHandler(handle:) ->
//       req
//       |> handle
//       |> app.run(ctx)
//       |> fn(result) {
//         case result {
//           Error(err) -> err |> to_err_resp
//           Ok(resp) -> resp
//         }
//       }
  }
}

fn run_app_handle_wisp(
  req req: Request(wisp.Connection),
  handle handle: fn(Request(wisp.Connection)) -> App(t, config, pubsub, user),
  ctx ctx: Context(config, pubsub, user),
  map_ok f: fn(t) -> resp.Response(wisp.Body),
) -> resp.Response(wisp.Body) {
  req
  |> handle
  |> app.run(ctx)
  |> fn(result) {
    case result {
      Ok(x) -> f(x)
      Error(err) -> err |> to_wisp_err_resp
    }
  }
}

// fn run_app_handle_mist(
//   req req: Request(mist.Connection),
//   handle handle: fn(Request(wisp.Connection)) -> App(t, config, pubsub, user),
//   map_ok f: fn(t) -> resp.Response(wisp.Body),
//   ctx ctx: Context(config, pubsub, user),
//   secret_key_base secret_key_base: String,
// ) -> resp.Response(mist.ResponseData) {
//   req
//   |> wisp_mist.handler(fn(req) {
//     req
//     |> handle
//     |> app.run(ctx)
//     |> fn(result) {
//       case result {
//         Ok(x) -> f(x)
//         Error(err) -> err |> to_wisp_err_resp
//       }
//     }
//   }, secret_key_base)
// }

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

    err.DbErr(..) |
    err.Err(..) ->
      wisp_html_resp(
        status: 500,
        element: html.text("Internal Server Error"),
        headers: dict.new(),
      )
  }
}

pub fn to_err_resp(
  err err: Err,
) -> resp.Response(mist.ResponseData) {
  case err {
    err.NotFound(..) ->
      mist_html_resp(
        status: 404,
        element: html.text("Not Found"),
        headers: dict.new(),
      )

    err.DbErr(..) |
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

fn build_web_req_handler(
  mist_req mist_req: Request(mist.Connection),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  secret_key_base secret_key_base: String,
  spec spec: Spec(config, pubsub, user),
  handle_wisp_mist handle_wisp_mist: fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData),
  handle_mist_websockets handle_mist_websockets: fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData),
  session_cookie_name session_cookie_name: String,
) -> resp.Response(mist.ResponseData) {
  let session =
    mist_req
    |> session.read_mist(name: session_cookie_name, secret_key_base:)

  let ctx = context.build(session:, cfg:, pubsub:, authenticate: spec.authenticate)

  case mist_req |> request.path_segments {
    [prefix, ..] if prefix == spec.websockets_path_prefix ->
      mist_req |> handle_mist_websockets(ctx)

    _ ->
      mist_req |> handle_wisp_mist(ctx)
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

fn default_wisp_response(
  req req: Request(wisp.Connection),
) -> resp.Response(wisp.Body) {
  case req |> wisp.path_segments {
    ["internal-server-error"] -> wisp.internal_server_error()
    ["unprocessable_entity"] -> wisp.unprocessable_content()
    ["method-not-allowed"] -> wisp.method_not_allowed([])
    ["entity-too-large"] -> wisp.content_too_large()
    ["bad-request"] -> wisp.bad_request("") // TODO
    _ -> wisp.not_found()
  }
}

fn default_mist_websockets_response(
  req _req: Request(mist.Connection),
) -> resp.Response(mist.ResponseData) {
  404
  |> resp.new
  |> resp.set_body(
    bytes_tree.new()
    |> mist.Bytes
  )
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
) -> EnvVar {
  dot_env.new()
  |> dot_env.set_path(relative_path)
  |> dot_env.set_debug(False)
  |> dot_env.load

  EnvVar(get_string: env.get_string)
}

fn static_directory(
  app_module_name app_module_name: String,
) {
  let assert Ok(priv_directory) = wisp.priv_directory(app_module_name)
  priv_directory <> "/static"
}
