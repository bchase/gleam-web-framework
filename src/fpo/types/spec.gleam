import gleam/otp/static_supervisor
import gleam/dict.{type Dict}
import gleam/http/response as resp
import gleam/http/request.{type Request}
import gleam/option.{type Option}
import lustre/element.{type Element}
import mist
import wisp
import fpo/types.{type Context, type Session, type Flags, type Features}
import fpo/monad/app.{type App}

pub type Spec(config, pubsub, user) {
  Spec(
    app_module_name: String,
    session_cookie_name: String,
    dot_env_relative_path: String,
    secret_key_base_env_var_name: String,
    //
    config: Config(config),
    add_pubsub_workers: fn(static_supervisor.Builder) -> #(static_supervisor.Builder, pubsub),
    authenticate: fn(Session, config) -> Option(user),
    //
    websockets_path_prefix: String,
    websockets_router: fn(Request(mist.Connection), Context(config, pubsub, user)) -> Result(resp.Response(mist.ResponseData), Nil),
    //
    router: fn(Request(wisp.Connection), Context(config, pubsub, user)) -> Result(Handler(config, pubsub, user), Nil),
  )
}

pub type Config(config) {
  Config(
    init: fn(Flags) -> config,
    features: Features,
  )
}

pub type Handler(config, pubsub, user) {
  WispHandler(handle: fn(Request(wisp.Connection), Context(config, pubsub, user)) -> resp.Response(wisp.Body))
  AppWispHandler(handle: fn(Request(wisp.Connection)) -> App(resp.Response(wisp.Body), config, pubsub, user))
  AppWispSessionCookieHandler(handle: fn(Request(wisp.Connection), Result(Session, Nil), String) -> App(resp.Response(wisp.Body), config, pubsub, user))
  AppLustreHandler(handle: fn(Request(wisp.Connection)) -> App(LustreResponse, config, pubsub, user))
  // MistHandler(handle: fn(Request(mist.Connection), Context(config, pubsub, user)) -> resp.Response(mist.ResponseData))
  // AppMistHandler(handle: fn(Request(mist.Connection)) -> App(resp.Response(mist.ResponseData), config, user))
}

pub type LustreResponse {
  LustreResponse(
    status: Int,
    headers: Dict(String, String),
    element: Element(Nil),
  )
}
