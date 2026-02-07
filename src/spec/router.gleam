import gleam/list
import gleam/string
import gleam/result
import gleam/option.{None}
import app/web/session
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import gleam/dict
import gleam/http/request.{type Request}
import app/types.{type Context}
import wisp
import app/types/spec.{type Handler}
import app/monad/app.{pure}
import spec/examples/counter
import spec/examples/counter_app
import spec/examples/server_component_elements as lscs

pub fn handler(
  req req: Request(wisp.Connection),
  ctx ctx: Context(config, pubsub, user),
) -> Result(Handler(config, pubsub, user), Nil) {
  case req |> wisp.path_segments {
    ["_user_client_info"] ->
      Ok(spec.AppWispSessionCookieHandler(handle: fn(req, session_cookie_name) {
        session.set_session_user_client_info_using_req_json_body(
          req:,
          session_cookie_name:,
        )
        |> result.lazy_unwrap(fn() {
          wisp.response(400)
        })
        |> pure
      }))

    [] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            html.p([], [
              html.text("Home"),
            ]),

            html.p([], [
              ctx.user_client_info
              |> string.inspect
              |> html.text
              |> list.wrap
              |> html.code([], _)
            ]),

            set_user_client_info_if_missing(ctx:),
          ]),
        ))
      }))

    //

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

    ["sqlite_demo"] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            lscs.sqlite_demo() |> lscs.element([], []),
            lustre_server_component_client_script(),
          ])
        ))
      }))

    ["postgres_demo"] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            lscs.postgres_demo() |> lscs.element([], []),
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

fn set_user_client_info_if_missing(
  ctx ctx: Context(config, pubsub, user),
) -> Element(msg) {
  html.div([], [
    case ctx.user_client_info {
      None ->
        html.meta([attr.name("no-user-client-info")])

      option.Some(_) ->
        html.text("")

    },

    html.script([
      attr.type_("module"),
      attr.src("/static/js/gleam-browser.js"),
    ], ""),
  ])
}
