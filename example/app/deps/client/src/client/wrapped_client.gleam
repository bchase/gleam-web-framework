import gleam/float
import gleam/int
import plinth/javascript/global
import gleam/string
import gleam/io
import gleam/option.{Some, None}
import gleam/pair
import lustre/effect.{type Effect}
import lustre_websocket.{type WebSocketEvent} as ws
import api/client.{type ApiClient, type Api}

pub opaque type Model(msg) {
  Model(
    ws_url: String,
    conn: Result(ws.WebSocket, Int),
    client: ApiClient(Api, Model(msg), Msg(msg)),
  )
}

pub opaque type Msg(msg) {
  NoOp
  // init/maintain websocket
  RecvWebSocketEvent(event: WebSocketEvent)
  ReconnectWebsocket(delay: Bool)
  // recv msgs
  RecvClientResp(msg: msg)
}

pub type ConnectionEvent {
  Connected
  Reconnected
  Disconnected
}

pub fn init(
  ws_url ws_url: String,
) -> #(Model(msg), Effect(Msg(msg))) {
  Model(
    ws_url:,
    conn: Error(0),
    client: client.init(
      get_client: fn(model: Model(msg)) { model.client },
      set_client: fn(model: Model(msg), client) { Model(..model, client:) },
      get_send: fn(model: Model(msg)) {
        case model.conn {
          Error(_) -> None
          Ok(conn) -> Some(ws.send(conn, _))
        }
      },
      encode: client.encode_api,
      on_no_conn: fn(_) { None },
    )
  )
  |> pair.new(effect.batch([
    effect.from(fn(dispatch) {
      dispatch(ReconnectWebsocket(delay: False))
    }),
  ]))
}

const base_delay_ms = 1000 // 1s
const max_delay_ms = 60_000 // 60s

pub fn update(
  model model: Model(msg),
  msg msg: Msg(msg),
) -> #(Model(msg), Effect(Msg(msg))) {
  case msg {
    NoOp ->
      pure(model)

    RecvClientResp(msg: _) -> // intercept at parent
      pure(model)

    RecvWebSocketEvent(event: ws.InvalidUrl) -> {
      io.println_error("Invalid URL: " <> model.ws_url)
      pure(model)
    }

    RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
      io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
      pure(model)
    }

    RecvWebSocketEvent(event: ws.OnOpen(conn)) ->
      connect_to_websocket(model:, conn:)

    RecvWebSocketEvent(event: ws.OnClose(reason)) ->
      reconnect_to_websocket_on_close(model:, reason:)

    ReconnectWebsocket(delay:) ->
      attempt_reconnect_to_websocket(model:, with_delay: delay)

    RecvWebSocketEvent(event: ws.OnTextMessage(msg)) ->
      model.client.recv(model, msg)
  }
}

// client helpers

pub fn exp_backoff_delay_ms(
  attempt attempt: Int,
  base_delay_ms base: Int,
  max_delay_ms max: Int,
) -> Int {
  let attempt =
    case attempt < 1 {
      True -> 1
      False -> attempt
    }

  let exp_delay =
    case int.power(2, int.to_float(attempt)) {
      Error(Nil) ->
        max

      Ok(mul) ->
        base
        |> int.to_float
        |> float.multiply(mul)
        |> float.round()
    }

  exp_delay
  |> int.clamp(min: base, max:)
  |> int.random
}

fn connect_to_websocket(
  model model: Model(msg),
  conn conn: ws.WebSocket,
) -> #(Model(msg), Effect(Msg(msg))) {
  io.println("WebSocket opened: " <> model.ws_url)

  let model = Model(..model, conn: Ok(conn))

  #(model, effect.batch([
    todo as "previously send initial effs for items & sub",
  ]))
}

fn reconnect_to_websocket_on_close(
  model model: Model(msg),
  reason reason: ws.WebSocketCloseReason,
) -> #(Model(msg), Effect(Msg(msg))) {
  io.println_error("WebSocket closed: " <> reason |> string.inspect)

  let conn =
    case model.conn {
      Ok(_conn) -> Error(0)
      Error(attempt) -> Error(attempt + 1)
    }

  Model(..model, conn:)
  |> eff([
    effect.from(fn(dispatch) {
      dispatch(ReconnectWebsocket(delay: True))
    }),
  ])
}

fn attempt_reconnect_to_websocket(
  model model: Model(msg),
  with_delay delay: Bool,
) -> #(Model(msg), Effect(Msg(msg))) {
  case model.conn, delay {
    Ok(_conn), _ ->
      pure(model)

    Error(attempt), True -> {
      Model(..model, conn: Error(attempt))
      |> pair.new(effect.batch([
        send_after(
          delay_ms: exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
          msg: ReconnectWebsocket(delay: False)),
      ]))
    }

    Error(_attempt), False -> {
      model
      |> pair.new(effect.batch([
        ws.init(model.ws_url, RecvWebSocketEvent),
      ]))
    }
  }
}

// lustre helpers

fn pure(
  model model: model,
) -> #(model, Effect(msg)) {
  model |> pair.new(effect.none())
}

fn eff(
  model model: model,
  effs effs: List(Effect(msg))
) -> #(model, Effect(msg)) {
  model |> pair.new(effect.batch(effs))
}

// lustre js helpers

fn send_after(
  delay_ms delay_ms: Int,
  msg msg: msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    global.set_timeout(delay_ms, fn() {
      echo delay_ms
      dispatch(msg)
    })
    Nil
  })
}
