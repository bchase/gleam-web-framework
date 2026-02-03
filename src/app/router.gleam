import lustre/element/html
import gleam/dict
import gleam/option.{type Option, Some, None}
import gleam/http/response.{type Response}
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp
import app/types/spec.{type Handler}
import app/monad/app.{pure, do}

pub fn handler(
  req req: Request(wisp.Connection),
  ctx _ctx: Context(config, user),
) -> Result(Handler(config, user), Nil) {
  case req |> wisp.path_segments {
    [] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.text("routed with `App` + lustre"),
        ))
      }))

    _ ->
      Error(Nil)
  }
}
