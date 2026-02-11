import gleam/bit_array
import gleam/erlang/process
import gleam/option.{type Option, Some, None}
import gleam/uri
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
import gleam/http.{Get, Put}
import gleam/http/response as resp
import gleam/http/request.{type Request}
import gleam/bytes_tree
import mist
import wisp/wisp_mist
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision.{type ChildSpecification}
import fpo/types.{type Context, type Session, type SecretKeyBase, type EnvVar, type Fpo, EnvVar, SecretKeyBase}
import fpo/context
import fpo/web/session
import fpo/monad/app.{type App}
import fpo/types/err.{type Err}
import fpo/types/spec.{type Spec, type Handler, Wisp, AppWisp, AppWispSessionCookie, AppLustre, LustreResponse}
import lustre/element.{type Element}
import wisp
import fpo/flags
import fpo/generic/guard
import fpo/generic/mist as fpo_mist
import fpo/generic/uri as fpo_uri
import lustre/attribute as attr
import fpo/lustre/server_component as lsc

const web_req_handler_worker_shutdown_ms = 60_000

pub fn supervised(
  spec spec: Spec(config, pubsub, user, err),
) -> static_supervisor.Builder {
  let #(supervisor, _, _, _) = init(spec:)
  supervisor
}

pub fn init(
  spec spec: Spec(config, pubsub, user, err),
) -> #(static_supervisor.Builder, config, pubsub, Fpo) {
  let env_var = load_dot_env(spec.dot_env_relative_path)

  let supervisor =
    static_supervisor.new(static_supervisor.OneForOne)

  let name = process.new_name("secret_key_base")
  let secret_key_base =
    spec.secret_key_base_env_var_name
    |> secret_key_base(env_var_name: _)
    |> bit_array.from_string
    |> fn(secret_key_base) {
      fn() { secret_key_base }
    }
  let supervisor =
    supervisor
    |> static_supervisor.add(supervised_secret_key_base(name:, secret_key_base:))
  let fpo = types.Fpo(secret_key_base: name, path_prefix: "", set_user_client_info: None)

  let #(supervisor, pubsub) =
    supervisor
    |> spec.add_pubsub_workers

  let #(flags, add_worker_funcs) =
    flags.build(features: spec.config.features, env_var:)

  let supervisor =
    supervisor
    |> list.fold(add_worker_funcs, _, fn(supervisor, add_worker) {
      supervisor |> add_worker
    })

  let cfg = spec.config.init(flags)

  let supervisor =
    supervisor
    |> static_supervisor.add(web_req_handler_worker(cfg:, spec:, pubsub:, fpo:))

  #(supervisor, cfg, pubsub, fpo)
}

fn supervised_secret_key_base(
  name name: process.Name(process.Subject(SecretKeyBase)),
  secret_key_base secret_key_base: fn() -> BitArray,
) -> ChildSpecification(process.Subject(process.Subject(SecretKeyBase))) {
  supervision.worker(fn() {
    let secret_key_base = secret_key_base()

    actor.new(Nil)
    |> actor.on_message(fn(state, reply) {
      process.send(reply, SecretKeyBase(secret_key_base))
      actor.continue(state)
    })
    |> actor.named(name)
    |> actor.start
  })
}

fn web_req_handler_worker(
  cfg cfg: config,
  pubsub pubsub: pubsub,
  spec spec: Spec(config, pubsub, user, err),
  fpo fpo: Fpo,
) -> ChildSpecification(Supervisor) {
  supervision.ChildSpecification(
    start: fn() { web_req_handler(cfg:, spec:, pubsub:, fpo:) },
    restart: supervision.Permanent,
    significant: False,
    child_type: supervision.Worker(shutdown_ms: web_req_handler_worker_shutdown_ms),
  )
}

const lsc_infix = "lsc"

fn web_req_handler(
  cfg cfg: config,
  pubsub pubsub: pubsub,
  spec spec: Spec(config, pubsub, user, err),
  fpo fpo: Fpo,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  let app_module_name = spec.app_module_name
  let session_cookie_name = spec.session_cookie_name

  let fpo_path_prefix =
    case spec.config.features.set_user_client_info {
      Some(info) -> info.path_prefix
      None -> ""
    }

  let secret_key_base =
    spec.secret_key_base_env_var_name
    |> secret_key_base(env_var_name: _)

  let handle_server_components_websockets =
    fn(req: Request(mist.Connection), ctx: Context(config, pubsub, user)) -> resp.Response(mist.ResponseData) {
      let path_prefix = ctx.fpo.path_prefix

      case req |> request.path_segments {
        [prefix, infix, ..route] if prefix == path_prefix && infix == lsc_infix ->
          spec.server_components
          |> lsc.for(route)
          |> result.map(fn(sc) { sc |> lsc.start(req, ctx) })
          |> result.lazy_unwrap(fn() { fpo_mist.empty_resp(404) })

        _ ->
          fpo_mist.empty_resp(404)
      }
    }

  let handle_wisp_mist =
    fn(req: Request(wisp.Connection), session: Result(Session, Nil), ctx: Context(config, pubsub, user)) -> resp.Response(wisp.Body) {
      case spec.router(req, ctx) {
        Error(Nil) ->
          case req.method, req |> wisp.path_segments {
            Get, [prefix, "user_client_info"] if prefix == fpo_path_prefix ->
              Ok(wisp_html_resp(
                status: 200,
                headers: dict.new(),
                element: view_set_user_client_info(
                  req:,
                  set_user_client_info: spec.config.features.set_user_client_info,
                ),
              ))

            Put, [prefix, "user_client_info"] if prefix == fpo_path_prefix ->
              case session.set_session_user_client_info_using_req_json_body(req:, session_cookie_name:) {
                Ok(resp) -> Ok(resp)
                Error(Nil) -> Ok(wisp.response(400))
              }

            _, _ ->
              Error(Nil)
          }

        Ok(handler) ->
          Ok(run_handler(req:, handler:, ctx:, session:, session_cookie_name:))
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
    fpo:,
    secret_key_base:,
    spec:,
    handle_wisp_mist:,
    handle_mist_websockets:,
    handle_server_components_websockets:,
    session_cookie_name:,
  )
  |> mist.new()
  |> mist.bind("0.0.0.0")
  |> mist.port(port())
  // |> mist.with_ipv6
  |> mist.start
}

fn to_mist(
  wisp_handler wisp_handler: fn(Request(wisp.Connection), Result(Session, Nil), Context(config, pubsub, user)) -> resp.Response(wisp.Body),
  secret_key_base secret_key_base: String,
  app_module_name app_module_name: String,
) -> fn(Request(mist.Connection), Result(Session, Nil), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData) {
  fn(mist_req, session, ctx) {
    fn(wisp_req) {
      use wisp_req <- middleware(wisp_req, static_directory(app_module_name:))
      wisp_handler(wisp_req, session, ctx)
    }
    |> wisp_mist.handler(secret_key_base)
    |> fn(handle_mist) { handle_mist(mist_req) }
  }
}

fn run_handler(
  req req: Request(wisp.Connection),
  handler handler: Handler(config, pubsub, user, err),
  ctx ctx: Context(config, pubsub, user),
  session session: Result(Session, Nil),
  session_cookie_name session_cookie_name: String,
) -> resp.Response(wisp.Body) {
  case handler {
    Wisp(handle:) ->
      req
      |> handle(ctx)

    AppWisp(handle:) ->
      req
      |> run_app_handle_wisp(handle:, ctx:, map_ok: fn(x) { x })

    AppWispSessionCookie(handle:) ->
      req
      |> run_app_handle_wisp(handle: handle(_, session, session_cookie_name), ctx:, map_ok: fn(x) { x })

    AppLustre(handle:) ->
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
  handle handle: fn(Request(wisp.Connection)) -> App(t, config, pubsub, user, err),
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
  err err: Err(err),
) -> resp.Response(wisp.Body) {
  case err {
    err.RedirectTo(location:, using:, ..) -> {
      let status =
        case using {
          err.Redirect302 -> 302
        }

      wisp_html_resp(
        status:,
        element: element.none(),
        headers: dict.from_list([
          #("location", location),
        ]),
      )
    }

    err.NotFound(..) ->
      wisp_html_resp(
        status: 404,
        element: html.text("Not Found"),
        headers: dict.new(),
      )

    err.SecretKeyBaseLookupFailed |
    err.HttpReqErr(..) |
    err.DbErr(..) |
    err.Err(..) |
    err.AppErr(..) ->
      wisp_html_resp(
        status: 500,
        element: html.text("Internal Server Error"),
        headers: dict.new(),
      )
  }
}

pub fn to_err_resp(
  err err: Err(err),
) -> resp.Response(mist.ResponseData) {
  case err {
    err.RedirectTo(location:, using:, ..) -> {
      let status =
        case using {
          err.Redirect302 -> 302
        }

      mist_html_resp(
        status:,
        element: element.none(),
        headers: dict.from_list([
          #("location", location),
        ]),
      )
    }

    err.NotFound(..) ->
      mist_html_resp(
        status: 404,
        element: html.text("Not Found"),
        headers: dict.new(),
      )

    err.SecretKeyBaseLookupFailed |
    err.HttpReqErr(..) |
    err.DbErr(..) |
    err.Err(..) |
    err.AppErr(..) ->
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

fn redirect_to_session_init(
  then_redirect_to_path redirect_to_path: String,
  features features: types.Features,
) -> resp.Response(mist.ResponseData) {
  let redirect_to = fn(location) {
    fpo_mist.empty_resp(302)
    |> resp.set_header("location", location)
  }

  use types.SetUserClientInfo(path_prefix, ..) <-
    guard.some_(features.set_user_client_info, fn() { redirect_to("/") })

  let redirect_to_path =
    uri.percent_encode(redirect_to_path)

  let location =
    fpo_uri.from(
      path: [ path_prefix, "user_client_info" ],
      params: [
        #("redirect_to_path", redirect_to_path),
      ]
    )
    |> uri.to_string

  redirect_to(location)
}

fn build_web_req_handler(
  mist_req mist_req: Request(mist.Connection),
  cfg cfg: config,
  pubsub pubsub: pubsub,
  fpo fpo: Fpo,
  secret_key_base secret_key_base: String,
  spec spec: Spec(config, pubsub, user, err),
  handle_wisp_mist handle_wisp_mist: fn(Request(mist.Connection), Result(Session, Nil), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData),
  handle_server_components_websockets handle_server_components_websockets: fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData),
  handle_mist_websockets handle_mist_websockets: fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData),
  session_cookie_name session_cookie_name: String,
) -> resp.Response(mist.ResponseData) {
  let features = spec.config.features

  let session =
    read_or_init_session(
      req: mist_req,
      secret_key_base:,
      session_cookie_name:,
      features:,
    )

  use session <- guard.ok_(session, fn(_err) {
    redirect_to_session_init(then_redirect_to_path: mist_req.path, features:)
  })


  let session = Ok(session)

  let ctx = context.build(
    cfg:,
    pubsub:,
    fpo:,
    session:,
    authenticate: spec.authenticate,
    features:,
  )

  let fpo_path_prefix = spec.config.features.fpo_path_prefix

  case mist_req |> request.path_segments {
    [prefix, infix, ..] if prefix == fpo_path_prefix && infix == lsc_infix -> {
      mist_req |> handle_server_components_websockets(ctx)
    }

    [prefix, ..] if prefix == spec.websockets_path_prefix ->
      mist_req |> handle_mist_websockets(ctx)

    _ ->
      mist_req |> handle_wisp_mist(session, ctx)
  }
}

fn read_or_init_session(
  req req: Request(mist.Connection),
  secret_key_base secret_key_base: String,
  session_cookie_name session_cookie_name: String,
  features features: types.Features,
) -> Result(Session, Nil) {
  req
  |> session.read_mist(name: session_cookie_name, secret_key_base:)
  |> fn(result) {
    case result, req |> request.path_segments {
      Ok(session), _ ->
        Ok(session)

      Error(Nil), _ -> {
        use types.SetUserClientInfo(path_prefix, browser_js_path) <-
          guard.some_(features.set_user_client_info, fn() {
            Error(Nil)
          })

        case req.path == browser_js_path, req |> request.path_segments {
          True, _ ->
            // allow `deps/browser` `.js` to load w/o session
            Ok(types.zero_session())

          False, [prefix, "user_client_info"] if prefix == path_prefix ->
            // allow `GET /$PREFIX/user_client_info` to load to perform PUT then redirect
            Ok(types.zero_session())

          False, _ ->
            Error(Nil)
        }
      }
    }
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
  fpo_mist.empty_resp(404)
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

//

fn view_set_user_client_info(
  req req: Request(conn),
  set_user_client_info info: Option(types.SetUserClientInfo),
) -> Element(msg) {
  use info <- guard.some(info, element.none())

  let redirect_to_path =
    req
    |> request.get_query
    |> result.unwrap([])
    |> list.key_find("redirect_to_path")
    |> result.unwrap("/")

  html.div([], [
    html.meta([
      attr.name("no-user-client-info"),
      attr.data("path_prefix", info.path_prefix),
      attr.data("redirect_to_path", redirect_to_path),
    ]),

    html.script([
      attr.type_("module"),
      attr.src(info.browser_js_path),
    ], ""),
  ])
}
