import gleam/json.{type Json}
import gleam/result
import gleam/float
import gleam/int
import plinth/javascript/global
import gleam/string
import gleam/io
import gleam/option.{Some, None, type Option}
import gleam/pair
import lustre/effect.{type Effect}
import lustre_websocket.{type WebSocketEvent} as ws
import api/client.{type ApiClient}

// pub type ConnectionEvent {
//   Connected(reconnect: Bool)
//   Disconnected
//   WebSocketUrlInvalid
// }

// pub fn is_connected(
//   client client: ModelWrapper(api, parent_msg),
// ) -> Bool {
//   case client {
//     ModelWrapper(model: None, ..) ->
//       False

//     ModelWrapper(model: Some(model), ..) ->
//       result.is_ok(model.conn)
//   }
// }

// pub type Initialized(api, parent_msg) {
//   Initialized(
//     client: ModelWrapper(api, parent_msg),
//     // send: fn(api) -> Effect(parent_msg),
//     send: fn(api) -> Nil,
//   )
// }

// pub fn parent_init(
//   ws_url ws_url: String,
//   encode encode: fn(api) -> Json,
//   wrap wrap: fn(MsgWrapper(api, parent_msg)) -> parent_msg,
//   recv to_parent_msg: fn(api) -> parent_msg,
//   conn notify_parent: fn(ConnectionEvent) -> Option(parent_msg),
//   initialized initialized: fn(Initialized(api, parent_msg)) -> parent_msg
// ) -> #(ModelWrapper(api, parent_msg), Effect(parent_msg)) {
//   uninitialized()
//   |> pair.new(effect.from(fn(dispatch_parent) {
//     dispatch_parent(wrap(GotParent(ws_url:, encode:, parent: Parent(
//       dispatch_parent:,
//       to_parent_msg:,
//       notify_parent:,
//       initialized:,
//     ))))
//   }))
// }

// pub fn parent_send(
//   client client: ModelWrapper(api, parent_msg),
//   req req: client.Req(api, Msg(api)),
//   set_client set_client: fn(parent_model, client) -> #(parent_model, Effect(parent_msg)),
//   wrap wrap: fn(MsgWrapper(api, parent_msg)) -> parent_msg,
// ) -> #(parent_model, Effect(parent_msg)) {
//   case client.model {
//     None -> todo as "move this `Option` up to parent?"
//     Some(model) -> {
//       model.client.send(model, req)
//       todo
//     }
//   }
// }

// pub fn uninitialized() -> ModelWrapper(api, parent_msg) {
//   ModelWrapper(
//     model: None,
//     send: fn(_) {
//       io.println_error("`send` was called before `dispatch_parent` was set")
//       // effect.from(fn(_) { Nil })
//       Nil
//     },
//   )
// }

// pub opaque type MsgWrapper(api, parent_msg) {
//   RecvSendReq(req: client.Req(api, parent_msg))
//   GotParent(
//     ws_url: String,
//     encode: fn(api) -> Json,
//     parent: Parent(api, parent_msg),
//   )
//   GotDispatchSelf(
//     ws_url: String,
//     encode: fn(api) -> Json,
//     parent: Parent(api, parent_msg),
//     dispatch_self: fn(MsgWrapper(api, parent_msg)) -> Nil,
//   )
//   InternalClientMsg(msg: Msg(api))
//   // RespondToParent(
//   //   parent: Parent(api, parent_msg),
//   //   dispatch_self: fn(MsgWrapper(api, parent_msg), parent_msg) -> Nil,
//   //   model: ModelWrapper(api, parent_msg)
//   // )
// }

// pub opaque type Parent(api, parent_msg) {
//   Parent(
//     dispatch_parent: fn(parent_msg) -> Nil,
//     to_parent_msg: fn(api) -> parent_msg,
//     initialized: fn(Initialized(api, parent_msg)) -> parent_msg,
//     notify_parent: fn(ConnectionEvent) -> Option(parent_msg),
//   )
// }

// pub fn update_(
//   model model: ModelWrapper(api, parent_msg),
//   msg msg: MsgWrapper(api, parent_msg),
// ) -> #(ModelWrapper(api, parent_msg), Effect(MsgWrapper(api, parent_msg))) {
//   case msg {
//     InternalClientMsg(msg:) ->
//       case model.model {
//         None ->
//           pure(model)

//         Some(m) -> {
//           let #(m, eff) = update(m, msg)

//           ModelWrapper(..model, model: Some(m))
//           |> pair.new(effect.batch([
//             eff |> effect.map(InternalClientMsg)
//           ]))
//         }
//       }

//     RecvSendReq(req:) -> {
//       let #(m, send_eff) =
//         case model.model {
//           None -> todo
//           Some(m) ->
//             m.client.send(m, req)
//         }

//       ModelWrapper(..model, model: Some(m))
//       |> pair.new(effect.batch([
//         send_eff |> effect.map(InternalClientMsg),
//       ]))
//     }

//     GotParent(ws_url:, encode:, parent:) ->
//       #(model, effect.from(fn(dispatch_self) {
//         dispatch_self(GotDispatchSelf(ws_url:, encode:, parent:, dispatch_self:))
//       }))

//     GotDispatchSelf(ws_url:, encode:, dispatch_self:, parent:) -> {
//       let #(m, eff) = init(ws_url:, parent:, encode:)

//       // let send = fn(req) {
//       //   effect.from(fn(dispatch) {
//       //     todo
//       //   })
//       // }

//       let send = todo

//       let model = ModelWrapper(model: Some(m), send:)

//       Initialized(client: model, send:)
//       |> m.parent.initialized()
//       |> m.parent.dispatch_parent

//       model
//       |> pair.new(effect.batch([
//         eff |> effect.map(InternalClientMsg)
//       ]))
//     }
//   }
// }

// pub opaque type ModelWrapper(api, parent_msg) {
//   ModelWrapper(
//     model: Option(Model(api, parent_msg)),
//     // send: fn(api) -> Effect(parent_msg),
//     send: fn(api) -> Nil,
//   )
// }

// //

// pub opaque type Model(api, parent_msg) {
//   Model(
//     ws_url: String,
//     parent: Parent(api, parent_msg),
//     conn: Result(ws.WebSocket, Int),
//     client: ApiClient(api, Model(api, parent_msg), Msg(api)),
//   )
// }

// pub opaque type Msg(api) {
//   NoOp
//   // init/maintain websocket
//   RecvWebSocketEvent(event: WebSocketEvent)
//   ReconnectWebSocket(delay: Bool)
//   // recv msgs
//   RecvClientResp(msg: api)
// }

// fn init(
//   ws_url ws_url: String,
//   parent parent: Parent(api, parent_msg),
//   encode encode: fn(api) -> Json,
// ) -> #(Model(api, parent_msg), Effect(Msg(api))) {
//   Model(
//     ws_url:,
//     conn: Error(0),
//     client: client.init(
//       get_client: fn(model: Model(api, parent_msg)) { model.client },
//       set_client: fn(model: Model(api, parent_msg), client) { Model(..model, client:) },
//       get_send: fn(model: Model(api, parent_msg)) {
//         case model.conn {
//           Error(_) -> None
//           Ok(conn) -> Some(ws.send(conn, _))
//         }
//       },
//       encode:,
//       on_no_conn: fn(_) { None },
//     ),
//     parent:,
//   )
//   |> pair.new(effect.batch([
//     effect.from(fn(dispatch) {
//       dispatch(ReconnectWebSocket(delay: False))
//     }),
//   ]))
// }

const base_delay_ms = 1000 // 1s
const max_delay_ms = 60_000 // 60s

// pub fn update(
//   model model: Model(api, parent_msg),
//   msg msg: Msg(api),
// ) -> #(Model(api, parent_msg), Effect(Msg(api))) {
//   case msg {
//     NoOp ->
//       pure(model)

//     RecvClientResp(msg: _) -> // intercept at parent
//       pure(model)

//     RecvWebSocketEvent(event: ws.InvalidUrl) -> {
//       io.println_error("Invalid URL: " <> model.ws_url)
//       pure(model)
//     }

//     RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
//       io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
//       pure(model)
//     }

//     RecvWebSocketEvent(event: ws.OnOpen(conn)) ->
//       connect_to_websocket(model:, conn:)

//     RecvWebSocketEvent(event: ws.OnClose(reason)) ->
//       reconnect_to_websocket_on_close(model:, reason:)

//     ReconnectWebSocket(delay:) ->
//       attempt_reconnect_to_websocket(model:, with_delay: delay)

//     RecvWebSocketEvent(event: ws.OnTextMessage(msg)) ->
//       model.client.recv(model, msg)
//   }
// }

// // client helpers

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

// fn connect_to_websocket(
//   model model: Model(api, parent_msg),
//   conn conn: ws.WebSocket,
// ) -> #(Model(api, parent_msg), Effect(Msg(api))) {
//   io.println("WebSocket opened: " <> model.ws_url)

//   let model = Model(..model, conn: Ok(conn))

//   #(model, effect.batch([
//     todo as "previously send initial effs for items & sub",
//   ]))
// }

// fn reconnect_to_websocket_on_close(
//   model model: Model(api, parent_msg),
//   reason reason: ws.WebSocketCloseReason,
// ) -> #(Model(api, parent_msg), Effect(Msg(api))) {
//   io.println_error("WebSocket closed: " <> reason |> string.inspect)

//   let conn =
//     case model.conn {
//       Ok(_conn) -> Error(0)
//       Error(attempt) -> Error(attempt + 1)
//     }

//   Model(..model, conn:)
//   |> eff([
//     effect.from(fn(dispatch) {
//       dispatch(ReconnectWebSocket(delay: True))
//     }),
//   ])
// }

// fn attempt_reconnect_to_websocket(
//   model model: Model(api, parent_msg),
//   with_delay delay: Bool,
// ) -> #(Model(api, parent_msg), Effect(Msg(api))) {
//   case model.conn, delay {
//     Ok(_conn), _ ->
//       pure(model)

//     Error(attempt), True -> {
//       Model(..model, conn: Error(attempt))
//       |> pair.new(effect.batch([
//         send_after(
//           delay_ms: exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
//           msg: ReconnectWebSocket(delay: False)),
//       ]))
//     }

//     Error(_attempt), False -> {
//       model
//       |> pair.new(effect.batch([
//         ws.init(model.ws_url, RecvWebSocketEvent),
//       ]))
//     }
//   }
// }

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

//
//
//
//
//

pub opaque type Conn {
  Conn(
    ws_url: String,
    ws: Result(ws.WebSocket, Int),
  )
}

pub opaque type ConnMsg(api) {
  RecvWebSocketEvent(event: WebSocketEvent)
  ReconnectWebSocket(with_delay: Bool)
}

pub fn ws(
  conn conn: Conn,
) -> Option(ws.WebSocket) {
  option.from_result(conn.ws)
}

pub fn is_connected(
  conn conn: Conn,
) -> Bool {
  result.is_ok(conn.ws)
}

pub fn init(
  ws_url ws_url: String,
  wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
) -> #(Conn, Effect(parent_msg)) {
  Conn(
    ws_url:,
    ws: Error(0),
  )
  |> pair.new(effect.batch([
    effect.from(fn(dispatch) {
      dispatch(to_parent_msg(ReconnectWebSocket(with_delay: False)))
    }),
  ]))
}

// pub fn update(
//   client client: ApiClient(api, Conn, parent_msg),
//   wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
//   conn model: Conn,
//   msg msg: ConnMsg(api),
//   set_conn set_conn: fn(Conn) -> model,
// ) -> #(model, Effect(parent_msg)) {
//   let map_parent_msg = fn(t: #(Conn, Effect(ConnMsg(api)))) {
//     #(t.0, t.1 |> effect.map(to_parent_msg))
//   }

//   case msg {
//     RecvWebSocketEvent(event: ws.OnTextMessage(msg)) ->
//       client.recv(model, msg)

//     RecvWebSocketEvent(event: ws.InvalidUrl) -> {
//       io.println_error("Invalid URL: " <> model.ws_url)
//       pure(model) |> map_parent_msg
//     }

//     RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
//       io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
//       pure(model) |> map_parent_msg
//     }

//     RecvWebSocketEvent(event: ws.OnOpen(conn)) ->
//       connect_to_websocket(model:, conn:) |> map_parent_msg

//     RecvWebSocketEvent(event: ws.OnClose(reason)) ->
//       reconnect_to_websocket_on_close(model:, reason:) |> map_parent_msg

//     ReconnectWebSocket(delay:) ->
//       attempt_reconnect_to_websocket(model:, with_delay: delay) |> map_parent_msg
//   }
//   |> fn(t) {
//     #(set_conn(t.0), t.1)
//   }
// }

// type Web

fn set_websocket_conn(
  conn conn: Conn,
  ws ws: ws.WebSocket,
) -> #(Conn, Effect(ConnMsg(api))) {
  io.println("WebSocket opened: " <> conn.ws_url)

  pure(Conn(..conn, ws: Ok(ws)))
}

fn reconnect_to_websocket_on_close(
  conn conn: Conn,
  reason reason: ws.WebSocketCloseReason,
) -> #(Conn, Effect(ConnMsg(api))) {
  io.println_error("WebSocket closed: " <> reason |> string.inspect)

  let ws =
    case conn.ws {
      Ok(_conn) -> Error(0)
      Error(attempt) -> Error(attempt + 1)
    }

  Conn(..conn, ws:)
  |> eff([
    effect.from(fn(dispatch) {
      dispatch(ReconnectWebSocket(with_delay: True))
    }),
  ])
}

fn attempt_reconnect_to_websocket(
  conn conn: Conn,
  with_delay delay: Bool,
) -> #(Conn, Effect(ConnMsg(api))) {
  case conn.ws, delay {
    Ok(_conn), _ ->
      pure(conn)

    Error(attempt), True -> {
      Conn(..conn, ws: Error(attempt))
      |> pair.new(effect.batch([
        send_after(
          delay_ms: exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
          msg: ReconnectWebSocket(with_delay: False)),
      ]))
    }

    Error(_attempt), False -> {
      conn
      |> pair.new(effect.batch([
        ws.init(conn.ws_url, RecvWebSocketEvent),
      ]))
    }
  }
}

pub fn update(
  model model: model,
  get_client get_client: fn(model) -> ApiClient(api, model, parent_msg),
  wrap to_parent_msg: fn(ConnMsg(api)) -> parent_msg,
  conn conn: Conn,
  msg msg: ConnMsg(api),
  set_conn set_conn: fn(model, Conn) -> model,
) -> #(model, Effect(parent_msg)) {
  let map_parent= fn(t : #(Conn, Effect(ConnMsg(api)))) {
    model
    |> set_conn(t.0)
    |> pair.new(effect.batch([
      t.1 |> effect.map(to_parent_msg),
    ]))
  }

  echo conn.ws_url

echo msg
  case msg {
    RecvWebSocketEvent(event: ws.OnTextMessage(msg)) ->
      model
      |> get_client
      |> fn(client) {
        client.recv(model, msg)
      }

    RecvWebSocketEvent(event: ws.InvalidUrl) -> {
      io.println_error("Invalid URL: " <> conn.ws_url)
      pure(model)
    }

    RecvWebSocketEvent(event: ws.OnBinaryMessage(ba)) -> {
      io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
      pure(model)
    }

    RecvWebSocketEvent(event: ws.OnOpen(ws)) ->
      set_websocket_conn(conn:, ws:) |> map_parent

    RecvWebSocketEvent(event: ws.OnClose(reason)) ->
      reconnect_to_websocket_on_close(conn:, reason:) |> map_parent

    ReconnectWebSocket(with_delay:) ->
      attempt_reconnect_to_websocket(conn:, with_delay:) |> map_parent
  }
}

// fn connect_to_websocket(
//   model model: Conn,
//   conn conn: ws.WebSocket,
// ) -> #(Conn, Effect(ConnMsg(api))) {
//   io.println("WebSocket opened: " <> model.ws_url)

//   let model = Conn(..model, conn: Ok(conn))

//   #(model, effect.batch([
//     todo as "previously send initial effs for items & sub",
//   ]))
// }

// fn reconnect_to_websocket_on_close(
//   model model: Conn,
//   reason reason: ws.WebSocketCloseReason,
// ) -> #(Conn, Effect(ConnMsg(api))) {
//   io.println_error("WebSocket closed: " <> reason |> string.inspect)

//   let conn =
//     case model.conn {
//       Ok(_conn) -> Error(0)
//       Error(attempt) -> Error(attempt + 1)
//     }

//   Conn(..model, conn:)
//   |> eff([
//     effect.from(fn(dispatch) {
//       dispatch(ReconnectWebSocket(delay: True))
//     }),
//   ])
// }

// fn attempt_reconnect_to_websocket(
//   model model: Conn,
//   with_delay delay: Bool,
// ) -> #(Conn, Effect(ConnMsg(api))) {
//   case model.conn, delay {
//     Ok(_conn), _ ->
//       pure(model)

//     Error(attempt), True -> {
//       Conn(..model, conn: Error(attempt))
//       |> pair.new(effect.batch([
//         send_after(
//           delay_ms: exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
//           msg: ReconnectWebSocket(delay: False)),
//       ]))
//     }

//     Error(_attempt), False -> {
//       model
//       |> pair.new(effect.batch([
//         ws.init(model.ws_url, RecvWebSocketEvent),
//       ]))
//     }
//   }
// }
