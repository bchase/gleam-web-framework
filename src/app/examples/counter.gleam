import gleam/int
import gleam/pair
import lustre
// import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component

const route = "/ws/counter"

pub fn element() -> Element(msg) {
  server_component.element([
    server_component.route(route)
  ], [])
}

pub fn component() -> lustre.App(t, Model, Msg) {
  lustre.application(init, update, view)
}

pub opaque type Model {
  Model(
    nil: Nil,
    count: Int,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  Model(
    nil: Nil,
    count: 0,
  )
  |> pair.new(effect.none())
}

pub opaque type Msg {
  NoOp
  Inc
  Dec
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    NoOp ->
      model
      |> pair.new(effect.none())

    Inc ->
      Model(..model, count: model.count + 1)
      |> pair.new(effect.none())

    Dec ->
      Model(..model, count: model.count - 1)
      |> pair.new(effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Simple Counter")]),

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
