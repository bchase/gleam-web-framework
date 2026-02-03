import gleam/dict.{type Dict}
import gleam/http/response as resp
import gleam/http/request.{type Request}
import gleam/option.{type Option}
import lustre/element.{type Element}
import mist
import wisp
import app/types.{type Context, type Session}
import app/monad/app.{type App}

pub type Spec(config, user) {
  Spec(
    dot_env_relative_path: String,
    secret_key_base_env_var_name: String,
    //
    init_config: fn() -> config,
    authenticate: fn(Session, config) -> Option(user),
    //
    websockets_path_prefix: String,
    websockets_router: fn(Request(mist.Connection), Context(config, user)) -> Result(resp.Response(mist.ResponseData), Nil),
    //
    router: fn(Request(wisp.Connection), Context(config, user)) -> Result(Handler(config, user), Nil),
  )
}

pub type Handler(config, user) {
  WispHandler(handle: fn(Request(wisp.Connection), Context(config, user)) -> resp.Response(wisp.Body))
  AppWispHandler(handle: fn(Request(wisp.Connection)) -> App(resp.Response(wisp.Body), config, user))
  AppLustreHandler(handle: fn(Request(wisp.Connection)) -> App(LustreResponse, config, user))
  // MistHandler(handle: fn(Request(mist.Connection), Context(config, user)) -> resp.Response(mist.ResponseData))
  // AppMistHandler(handle: fn(Request(mist.Connection)) -> App(resp.Response(mist.ResponseData), config, user))
}

pub type LustreResponse {
  LustreResponse(
    status: Int,
    headers: Dict(String, String),
    element: Element(Nil),
  )
}
