import gleam/option.{type Option, Some, None}
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp
import app/types/spec.{type Handler}

pub fn handler(
  req req: Request(wisp.Connection),
  ctx _ctx: Context(config, user),
) -> Result(Handler(config, user), Nil) {
  case req |> wisp.path_segments {
    _ ->
      Error(Nil)
  }
}
