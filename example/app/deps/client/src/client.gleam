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
import api
import api/generic.{List}
import youid/uuid.{type Uuid}

fn send(
  conn conn: ws.WebSocket,
  req req: api.Req,
) -> Effect(Msg) {
  req
  |> build_socket_req
  |> api.encode_socket_req
  |> json.to_string
  |> ws.send(conn, _)
}

fn build_socket_req(
  req req: api.Req,
) -> api.SocketReq {
  api.socket_req(ref: uuid.v7() |> uuid.to_string, req:)
}

type SocketResp {
  SocketResp(
    ref: Uuid,
    result: Result(api.Resp, api.Err)
  )
}

fn decoder_socket_resp(
) -> Decoder(SocketResp) {
  api.decoder_socket_resp()
  |> decode.then(fn(sr) {
    case sr.ref |> uuid.from_string {
      Ok(ref) -> decode.success(SocketResp(ref:, result: sr.result))
      Error(Nil) -> decode.failure(zero_socket_resp(), "Failed to parse UUID ref:" <> sr.ref)
    }
  })
}

fn zero_socket_resp() -> SocketResp {
  SocketResp(ref: uuid.v7(), result: Error(api.zero_err()))
}

// gleam run -m lustre/dev build --no-html --minify

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
    items: List(api.Item),
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
  case msg |> echo {
    NoOp ->
      pure(model)

    GotWebSocketEvent(event: ws.OnOpen(conn)) -> {
      echo "WebSocket opened"
      Model(..model, conn: Some(conn))
      |> eff([
        send(conn, api.CrudItems(List(None))),
      ])
    }

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
  echo "WebSocket msg: " <> msg

  pure(model)
}

fn view(
  model model: Model,
) -> Element(Msg) {
  html.div([], [
    html.text("hi"),
  ])
}

//

fn pure(
  model model: Model,
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.none())
}

fn eff(
  model model: Model,
  effs effs: List(Effect(Msg))
) -> #(Model, Effect(Msg)) {
  model |> pair.new(effect.batch(effs))
}
