// import gleam/result
// import gleam/float
// import gleam/int
// import plinth/javascript/global
// import gleam/string
// import gleam/io
// import gleam/option.{type Option}
// import gleam/pair
// import lustre/effect.{type Effect}
// import lustre_websocket.{type WebSocketEvent} as ws
// import api/client.{type Client}

// pub fn ws(
//   conn conn: Conn(parent_msg),
// ) -> Option(ws.WebSocket) {
//   option.from_result(conn.ws)
// }

// pub fn is_connected(
//   conn conn: Conn(parent_msg),
// ) -> Bool {
//   result.is_ok(conn.ws)
// }

// const base_delay_ms = 1_000 // 1s
// const max_delay_ms = 60_000 // 60s

// pub opaque type Conn(parent_msg) {
//   Conn(
//     ws_url: String,
//     ws: Result(ws.WebSocket, Int),
//     notify: fn(ConnectionEvent) -> parent_msg,
//   )
// }

// pub opaque type ConnMsg(api) {
//   RecvWebSocketEvent(event: WebSocketEvent)
//   ReconnectWebSocket(with_delay: Bool)
// }

// pub opaque type InternalConnMsg(ws, close_reason) {
//   RecvWebSocketInvalidUrlErr
//   RecvWebSocketBinaryMessage(msg: BitArray)
//   RecvWebSocketTextMessage(msg: String)
//   RecvWebSocketOpen(ws: ws)
//   RecvWebSocketClose(reason: close_reason)
//   GotReconnectWebSocket(with_delay: Bool)
// }

// pub type ConnectionEvent {
//   Connected(reconnect: Bool)
//   Disconnected
//   WebSocketUrlInvalid
// }

// pub fn init(
//   ws_url ws_url: String,
//   wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
//   notify notify: fn(ConnectionEvent) -> parent_msg,
// ) -> #(Conn(parent_msg), Effect(parent_msg)) {
//   Conn(
//     ws_url:,
//     ws: Error(0),
//     notify:,
//   )
//   |> pair.new(effect.batch([
//     effect.from(fn(dispatch) {
//       dispatch(to_parent_msg(ReconnectWebSocket(with_delay: False)))
//     }),
//   ]))
// }

// pub fn update_(
//   model model: model,
//   get_client get_client: fn(model) -> Client(api, model, parent_msg),
//   wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
//   conn conn: Conn(parent_msg),
//   msg msg: InternalConnMsg(ws, close_reason),
//   set_conn set_conn: fn(model, Conn(parent_msg)) -> model,
// ) -> #(model, Effect(parent_msg)) {
//   let map_parent= fn(t: #(Conn(parent_msg), Effect(ConnMsg(api)))) {
//     model
//     |> set_conn(t.0)
//     |> pair.new(effect.batch([
//       t.1 |> effect.map(to_parent_msg),
//     ]))
//   }

//   let client = get_client(model)

//   case msg {
//     RecvWebSocketBinaryMessage(msg: ba) ->
//       ignore_binary_msg(model:, ba:)

//     RecvWebSocketTextMessage(msg:) ->
//       client.recv(model, msg)

//     RecvWebSocketInvalidUrlErr ->
//       notify_invalid_url(model:, conn:)

//     RecvWebSocketOpen(ws:) ->
//       set_websocket_conn(model:, conn:, ws: todo, set_conn:)

//     RecvWebSocketClose(reason:) ->
//       reconnect_to_websocket_on_close(conn:, reason: todo) |> map_parent

//     GotReconnectWebSocket(with_delay:) ->
//       attempt_reconnect_to_websocket(conn:, with_delay:) |> map_parent
//   }
// }

// pub fn update(
//   model model: model,
//   get_client get_client: fn(model) -> Client(api, model, parent_msg),
//   wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
//   conn conn: Conn(parent_msg),
//   msg msg: ConnMsg(api),
//   set_conn set_conn: fn(model, Conn(parent_msg)) -> model,
// ) -> #(model, Effect(parent_msg)) {
//   let map_parent= fn(t: #(Conn(parent_msg), Effect(ConnMsg(api)))) {
//     model
//     |> set_conn(t.0)
//     |> pair.new(effect.batch([
//       t.1 |> effect.map(to_parent_msg),
//     ]))
//   }

//   let client = get_client(model)

//   case msg {
//     RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) ->
//       ignore_binary_msg(model:, ba:)

//     RecvWebSocketEvent(event: ws.OnTextMessage(msg)) ->
//       client.recv(model, msg)

//     RecvWebSocketEvent(event: ws.InvalidUrl) ->
//       notify_invalid_url(model:, conn:)

//     RecvWebSocketEvent(event: ws.OnOpen(ws)) ->
//       set_websocket_conn(model:, conn:, ws:, set_conn:)

//     RecvWebSocketEvent(event: ws.OnClose(reason)) ->
//       reconnect_to_websocket_on_close(conn:, reason:) |> map_parent

//     ReconnectWebSocket(with_delay:) ->
//       attempt_reconnect_to_websocket(conn:, with_delay:) |> map_parent
//   }
// }

// fn set_websocket_conn(
//   model model,
//   conn conn: Conn(parent_msg),
//   ws ws: ws.WebSocket,
//   set_conn set_conn: fn(model, Conn(parent_msg)) -> model,
// ) -> #(model, Effect(parent_msg)) {
//   io.println("WebSocket opened: " <> conn.ws_url)

//   model
//   |> set_conn(Conn(..conn, ws: Ok(ws)))
//   |> pair.new(effect.batch([
//     effect.from(fn(dispatch) {
//       dispatch(conn.notify(Connected(reconnect: False)))
//     }),
//   ]))
// }

// fn reconnect_to_websocket_on_close(
//   conn conn: Conn(parent_msg),
//   reason reason: ws.WebSocketCloseReason,
// ) -> #(Conn(parent_msg), Effect(ConnMsg(api))) {
//   io.println_error("WebSocket closed: " <> reason |> string.inspect)

//   let ws =
//     case conn.ws {
//       Ok(_conn) -> Error(0)
//       Error(attempt) -> Error(attempt + 1)
//     }

//   Conn(..conn, ws:)
//   |> eff([
//     effect.from(fn(dispatch) {
//       dispatch(ReconnectWebSocket(with_delay: True))
//     }),
//   ])
// }

// fn attempt_reconnect_to_websocket(
//   conn conn: Conn(parent_msg),
//   with_delay delay: Bool,
// ) -> #(Conn(parent_msg), Effect(ConnMsg(api))) {
//   case conn.ws, delay {
//     Ok(_conn), _ ->
//       pure(conn)

//     Error(attempt), True -> {
//       Conn(..conn, ws: Error(attempt))
//       |> pair.new(effect.batch([
//         send_after(
//           delay_ms: exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
//           msg: ReconnectWebSocket(with_delay: False)),
//       ]))
//     }

//     Error(_attempt), False -> {
//       conn
//       |> pair.new(effect.batch([
//         ws.init(conn.ws_url, RecvWebSocketEvent),
//       ]))
//     }
//   }
// }

// fn ignore_binary_msg(
//   model model: model,
//   ba ba: BitArray,
// ) -> #(model, Effect(parent_msg)) {
//   io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
//   pure(model)
// }

// fn notify_invalid_url(
//   model model: model,
//   conn conn: Conn(parent_msg),
// ) -> #(model, Effect(parent_msg)) {
//   io.println_error("Invalid URL: " <> conn.ws_url)

//   model
//   |> pair.new(effect.batch([
//     effect.from(fn(dispatch) {
//       dispatch(conn.notify(WebSocketUrlInvalid))
//     }),
//   ]))
// }

// // helpers

// pub fn exp_backoff_delay_ms(
//   attempt attempt: Int,
//   base_delay_ms base: Int,
//   max_delay_ms max: Int,
// ) -> Int {
//   let attempt =
//     case attempt < 1 {
//       True -> 1
//       False -> attempt
//     }

//   let exp_delay =
//     case int.power(2, int.to_float(attempt)) {
//       Error(Nil) ->
//         max

//       Ok(mul) ->
//         base
//         |> int.to_float
//         |> float.multiply(mul)
//         |> float.round()
//     }

//   exp_delay
//   |> int.clamp(min: base, max:)
//   |> int.random
// }

// // lustre helpers

// fn pure(
//   model model: model,
// ) -> #(model, Effect(msg)) {
//   model |> pair.new(effect.none())
// }

// fn eff(
//   model model: model,
//   effs effs: List(Effect(msg))
// ) -> #(model, Effect(msg)) {
//   model |> pair.new(effect.batch(effs))
// }

// // lustre js helpers

// fn send_after(
//   delay_ms delay_ms: Int,
//   msg msg: msg,
// ) -> Effect(msg) {
//   effect.from(fn(dispatch) {
//     global.set_timeout(delay_ms, fn() {
//       dispatch(msg)
//     })
//     Nil
//   })
// }
