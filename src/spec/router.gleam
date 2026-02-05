import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import gleam/dict
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp
import app/examples/counter
import app/examples/counter_app
import app/examples/server_component_elements as lscs
import app/types/spec.{type Handler}
import app/monad/app.{pure}

pub fn handler(
  req req: Request(wisp.Connection),
  ctx _ctx: Context(config, pubsub, user),
) -> Result(Handler(config, pubsub, user), Nil) {
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
            counter.element(),
            lustre_server_component_client_script(),
          ])
        ))
      }))

    ["counter_app"] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            counter_app.element(),
            lustre_server_component_client_script(),
          ])
        ))
      }))

    ["pubsub_demo"] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            lscs.pubsub_demo() |> lscs.element([], []),
            lustre_server_component_client_script(),
          ])
        ))
      }))

    _ ->
      Error(Nil)
  }
}

fn lustre_server_component_client_script() -> Element(msg) {
  html.script([
    attr.type_("module"),
    attr.src("/static/js/lustre-server-component.min.mjs"),
  ], "")
}
