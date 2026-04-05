import lustre/effect.{type Effect}
import gleam/option.{type Option}
import gleam/json.{type Json}
import api/client
import lustre_websocket as ws
import plinth/javascript/global

pub type Client(req, model, msg) = client.Client(req, ws.WebSocket, ws.WebSocketEvent, ws.WebSocketCloseReason, model, msg)

pub type Msg = client.Msg(ws.WebSocket, ws.WebSocketCloseReason)

pub fn update(
  model model: model,
  client client: Client(api, model, msg),
  wrap wrap: fn(Msg) -> msg,
  msg msg: Msg,
  set_client set_client: fn(model, Client(api, model, msg)) -> model,
) -> #(model, Effect(msg)) {
  client.update(model:, client:, wrap:, msg:, set_client:)
}

pub fn init(
  model model: model,
  ws_url ws_url: String,
  //
  get_client get_client: fn(model) -> Client(req, model, msg),
  set_client set_client: fn(model, Client(req, model, msg)) -> model,
  wrap wrap: fn(Msg) -> msg,
  encode encode: fn(req) -> Json,
  notify notify: fn(client.ConnectionEvent) -> Option(msg),
  on_no_conn on_no_conn: fn(model) -> Option(msg),
) -> #(model, Effect(msg)) {
  client.init(model:, ws_url:, get_client:, set_client:, encode:, notify:, on_no_conn:, impl: impl(wrap:))
}

fn impl(
  wrap wrap: fn(Msg) -> msg,
) -> client.WebSocketImpl(ws.WebSocket, ws.WebSocketEvent, ws.WebSocketCloseReason, msg) {
  client.WebSocketImpl(connect:, send:, event:, wrap:, send_after:)
}

const connect = ws.init

fn send(
  msg msg: String,
  ws ws: ws.WebSocket,
) -> Effect(msg) {
  ws.send(ws, msg)
}

fn event(
  event event: ws.WebSocketEvent,
) -> Msg {
  case event {
    ws.InvalidUrl -> client.invalid_url
    ws.OnOpen(ws) -> client.ws_open(ws)
    ws.OnTextMessage(msg) -> client.ws_text_message(msg)
    ws.OnBinaryMessage(msg) -> client.ws_binary_message(msg)
    ws.OnClose(reason) -> client.ws_close(reason)
  }
}

fn send_after(
  delay_ms delay_ms: Int,
  msg msg: msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    global.set_timeout(delay_ms, fn() {
      dispatch(msg)
    })
    Nil
  })
}
