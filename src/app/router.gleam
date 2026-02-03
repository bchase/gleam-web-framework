import lustre/attribute as attr
import lustre/server_component
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

    ["counter"] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            server_component.element([
              server_component.route("/ws/counter")
            ], []),
            html.script([
              attr.type_("module"),
              attr.src("/static/js/lustre-server-component.min.mjs"),
            ], ""),
          ])
        ))
      }))

    _ ->
      Error(Nil)
  }
}
