import gleam/bit_array
import gleam/string
import gleam/io
import gleam/option.{type Option, Some, None}
import gleam/json.{type Json}
import gleam/dynamic/decode.{type Decoder}
import lustre/component
import lustre/element.{type Element}
import lustre/element/html
import gleam/pair
import lustre/effect.{type Effect}
import lustre
import lustre_websocket.{type WebSocketEvent} as ws

// build-kohort-components:
// 	(cd deps/kohort_components/ && \
// 	  gleam run -m lustre/dev build --no-html --minify)

pub fn main() -> Nil {
  register_web_component()
}

const tag_name = "fpo-example-client-component"

fn register_web_component() -> Nil {
  let component = lustre.component(init, update, view, decoders())
  let assert Ok(_) = lustre.register(component, tag_name)

  Nil
}

fn decoders() -> List(component.Option(Msg)) {
  [
    // component.on_attribute_change("", fn(str) { Error(Nil) }),
    // component.on_property_change("", decode.string |> decode.map(msg)),
  ]
}

type Model {
  Model(
    conn: Option(ws.WebSocket),
    items: List(Item),
  )
}

type Msg {
  NoOp
  GotWebSocketEvent(event: WebSocketEvent)
}

fn init(_) -> #(Model, Effect(Msg)) {
  Model(
    conn: None,
    items: [],
  )
  |> pair.new(effect.batch([
    ws.init(ws_url, GotWebSocketEvent),
  ]))
}

const ws_url = "/ws/api"

fn update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    NoOp ->
      pure(model)

    GotWebSocketEvent(event: ws.OnOpen(conn)) ->
      pure(Model(..model, conn: Some(conn)))

    GotWebSocketEvent(event: ws.OnClose(reason)) -> {
      io.println_error("WebSocket closed: " <> reason |> string.inspect)
      pure(Model(..model, conn: None))
    }

    GotWebSocketEvent(event: ws.InvalidUrl) -> {
      io.println_error("Invalid URL: " <> ws_url)
      pure(model)
    }

    GotWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
      io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
      pure(Model(..model, conn: None))
    }

    GotWebSocketEvent(event: ws.OnTextMessage(msg)) ->
      handle_websocket_text(model:, msg:)

  }
}

fn handle_websocket_text(
  model model: Model,
  msg msg: String,
) -> #(Model, Effect(Msg)) {
  todo
}

//

type Req

fn send_msg(
  conn conn: Option(ws.WebSocket),
  req req: Req,
) -> Nil {
}

//

fn pure(
  model model: Model,
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.none())
}

fn view(
  model model: Model,
) -> Element(Msg) {
  html.div([], [
    html.text("hi"),
  ])
}

// app shared

type Item {
  Item(
    id: Id(Item, String),
    name: String,
  )
}

// generic shared

type IdString(resource) = Id(resource, String)

fn decoder_id_string() -> Decoder(IdString(resource)) {
  decoder_id(decoder: decode.string)
}

fn encode(
  value value: IdString(resource),
) {
  encode_id(value:, encode: json.string)
}

type Id(resource, t) {
  Id(id: t)
}

fn decoder_id(
  decoder decoder: Decoder(t),
) -> Decoder(Id(resource, t)) {
  decoder
  |> decode.map(Id)
}

fn encode_id(
  value value: Id(resource, t),
  encode encode: fn(t) -> Json
) -> Json {
  encode(value.id)
}
