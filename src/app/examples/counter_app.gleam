import app/monad/app.{type App}
import app/types.{type Context}
import app/lustre/server_component as lsc
import app/lustre.{continue} as _
import gleam/erlang/process.{type Selector}
import gleam/option.{type Option, None}
import gleam/int
import lustre
// import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component

const route = "/ws/counter_app"

pub fn element() -> Element(msg) {
  server_component.element([
    server_component.route(route)
  ], [])
}

pub fn component(
  ctx ctx: Context(config, user),
) -> lustre.App(Context(config, user), Model, lsc.Wrapped(Msg)) {
  lsc.build_lustre_app(
    init:,
    post_init: None,
    selectors:,
    update:,
    view:,
    module: "app/examples/counter_app",
    ctx:,
)
}

fn selectors(
  model _model: Model,
) -> List(App(Selector(Msg), config, user)) {
  []
}

pub opaque type Model {
  Model(
    nil: Nil,
    count: Int,
  )
}

fn init() -> App(#(Model, Effect(Msg)), config, user) {
  Model(
    nil: Nil,
    count: 0,
  )
  |> continue([])
}

pub opaque type Msg {
  NoOp
  Inc
  Dec
}

fn update(
  model: Model,
  msg: Msg,
) -> App(#(Model, Effect(Msg)), config, user) {
  case msg {
    NoOp ->
      model
      |> continue([])

    Inc ->
      Model(..model, count: model.count + 1)
      |> continue([])

    Dec ->
      Model(..model, count: model.count - 1)
      |> continue([])
  }
}

fn view(
  model: Model,
  _user: Option(user),
  _user_client_info: types.UserClientInfo,
) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("App Counter")]),

    html.button([
      event.on_click(Dec),
    ], [
      html.text("-"),
    ]),

    html.span([], [
      html.text(model.count |> int.to_string),
    ]),

    html.button([
      event.on_click(Inc),
    ], [
      html.text("+"),
    ]),
  ])
}
