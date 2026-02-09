import fpo/types/err
import gleam/bool
import app/domain/users/sqlite as users
import app/types.{type Config} as _
import app/user.{type User}
import app/web/components/counter
import app/web/components/counter_app
import app/web/components/server_component_elements as lscs
import fpo/monad/app.{type App, do, pure}
import fpo/types.{type Context}
import fpo/types/spec.{type Handler}
import fpo/web/authe
import fpo/web/session
import fpo/generic/wisp as fpo_wisp
import fpo/generic/guard
import gleam/dict
import gleam/http.{Get, Put, Post, Delete}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{None}
import gleam/result.{try}
import gleam/string
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import wisp
import formal/form

pub fn handler(
  req req: Request(wisp.Connection),
  ctx ctx: Context(config, pubsub, user),
) -> Result(Handler(Config, pubsub, User), Nil) {
  case req.method, req |> wisp.path_segments {
    _, [] ->
      Ok(spec.AppLustreHandler(handle: fn(_req) {
        pure(spec.LustreResponse(
          status: 200,
          headers: dict.new(),
          element: html.div([], [
            html.div([], [
              html.form([
                attr.style("display", "inline"),
                attr.method("POST"),
                attr.action("/auth/session"),
              ], [
                html.input([
                  attr.name("email"),
                  attr.value(good_email),
                ]),

                html.input([
                  attr.name("password"),
                  attr.value(good_password),
                ]),

                html.button([
                  attr.type_("submit"),
                ], [
                  html.text("sign in"),
                ]),
              ]),

              html.text(" | "),

              html.form([
                attr.style("display", "inline"),
                ..fpo_wisp.action(method: Delete, path: "/auth/session")
              ], [
                html.button([
                  attr.type_("submit"),
                ], [
                  html.text("sign out"),
                ]),
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
          ]),
        ))
      }))

    //

    Post, ["auth", "session"] ->
      authe.sign_in(
        redirect_to: "/",
        get_user:,
        persist_user_token: user.insert_user_token,
      )

    Delete, ["auth", "session"] ->
      authe.sign_out(
        delete_user_token: user.delete_user_token,
      )

    //

    _, ["counter"] ->
      Ok(server_component_handler(
        component: lscs.counter(),
      ))

    _, ["counter_app"] ->
      Ok(server_component_handler(
        component: lscs.counter_app(),
      ))

    _, ["pubsub_demo"] ->
      Ok(server_component_handler(
        component: lscs.pubsub_demo(),
      ))

    _, ["sqlite_demo"] ->
      Ok(server_component_handler(
        component: lscs.sqlite_demo(),
      ))

    _, ["postgres_demo"] ->
      Ok(server_component_handler(
        component: lscs.postgres_demo(),
      ))

    _, _ ->
      Error(Nil)
  }
}

fn server_component_handler(
  component component: lscs.ServerComponentElement,
) -> Handler(config, pubsub, user) {
  spec.AppLustreHandler(handle: fn(_req) {
    pure(spec.LustreResponse(
      status: 200,
      headers: dict.new(),
      element: html.div([], [
        component |> lscs.element([], []),
        lustre_server_component_client_script(),
      ])
    ))
  })
}

pub type Login {
  Login(
    email: String,
    password: String,
  )
}

fn form_login() -> form.Form(Login) {
  form.new({
    use email <- form.field("email", { form.parse_string |> form.check_not_empty })
    use password <- form.field("password", { form.parse_string |> form.check_not_empty })
    form.success(Login(email:, password:))
  })
}

const good_email = "user@example.com"
const good_password = "good_password"

fn get_user(
  req req: Request(wisp.Connection)
) -> App(User, Config, pubsub, User) {
  let form = fpo_wisp.read_form(req:, form: form_login())
  use login <- guard.ok_(form, fn(_err) { app.redirect(to: "/") })

  let good_login = login.email == good_email && login.password == good_password
  use <- bool.lazy_guard(!good_login, fn() { app.redirect(to: "/") })

  pure(users.User(id: 1, name: ""))
}

fn lustre_server_component_client_script() -> Element(msg) {
  html.script([
    attr.type_("module"),
    attr.src("/static/js/lustre-server-component.min.mjs"),
  ], "")
}
