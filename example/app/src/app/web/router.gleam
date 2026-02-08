import gleam/list
import gleam/string
import gleam/result
import gleam/option.{None}
import fpo/web/session
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import gleam/dict
import gleam/http.{Get}
import gleam/http/request.{type Request}
import fpo/types.{type Context}
import wisp
import fpo/types/spec.{type Handler}
import fpo/monad/app.{type App, pure, do}
import fpo/web/authe
import app/web/components/counter
import app/web/components/counter_app
import app/web/components/server_component_elements as lscs
import app/user.{type User}
import app/types.{type Config} as _
import app/domain/users/sqlite as users

pub fn handler(
  req req: Request(wisp.Connection),
  ctx ctx: Context(config, pubsub, user),
) -> Result(Handler(Config, pubsub, User), Nil) {
  case req.method, req |> wisp.path_segments {
    _, ["_user_client_info"] ->
      Ok(spec.AppWispSessionCookieHandler(handle: fn(req, _session, session_cookie_name) {
        session.set_session_user_client_info_using_req_json_body(
          req:,
          session_cookie_name:,
        )
        |> result.lazy_unwrap(fn() {
          wisp.response(400)
        })
        |> pure
      }))

    _, [] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            html.div([], [
              html.a([
                attr.href("/auth/session/create"),
              ], [
                html.text("sign in"),
              ]),

              html.text(" | "),

              html.a([
                attr.href("/auth/session/delete"),
              ], [
                html.text("sign out"),
              ]),
            ]),

            html.p([], [
              html.text("Home"),
            ]),

            html.p([], [
              ctx.user
              |> string.inspect
              |> html.text
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

    _, ["auth", "session", "create"] -> {
      let dummy_user = users.User(id: 1, name: "")

      authe.sign_in(
        user: dummy_user,
        redirect_to: "/",
        persist_user_token: user.insert_user_token,
      )
    }

    _, ["auth", "session", "delete"] -> {
      authe.sign_out(
        delete_user_token: user.delete_user_token,
      )
    }

    //

    _, ["counter"] ->
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

    _, ["counter_app"] ->
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

    _, ["sqlite_demo"] ->
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

    _, ["postgres_demo"] ->
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

    _, ["pubsub_demo"] ->
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

    _, _ ->
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
      attr.src("/static/js/fpo-gleam-browser.js"),
    ], ""),
  ])
}
