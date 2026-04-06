import gleam/float
import gleam/int
import fpo/api/ws/client/req.{type RecvErr, type Req, type Reqs, NoConn, clear_req_and_log_err}
import fpo/api/ws/types
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/io
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import lustre/effect.{type Effect}
import youid/uuid.{type Uuid}

pub type Err = req.Err

pub type Client(req, ws, ws_event, close_reason, model, msg) {
  Client(
    // mutable
    ws: Conn(ws),
    reqs: Reqs(msg),
    reconnected: Bool,
    // static ws
    ws_url: String,
    impl: WebSocketImpl(ws, ws_event, close_reason, msg),
    // static parent
    set_client: fn(model, Client(req, ws, ws_event, close_reason, model, msg)) -> model,
    wrap: fn(Msg(ws, close_reason)) -> msg,
    notify: fn(ConnectionEvent) -> Option(msg),
    // public "methods"
    send: fn(model, Req(req, msg)) -> #(model, Effect(msg)),
    recv: fn(model, String) -> #(model, Effect(msg)),
  )
}

pub type WebSocketImpl(ws, ws_event, close_reason, msg) {
  WebSocketImpl(
    connect: fn(String, fn(ws_event) -> Msg(ws, close_reason)) -> Effect(Msg(ws, close_reason)),
    send: fn(String, ws) -> Effect(msg),
    wrap: fn(Msg(ws, close_reason)) -> msg,
    event: fn(ws_event) -> Msg(ws, close_reason),
    //
    send_after: fn(Int, msg) -> Effect(msg),
  )
}

pub fn zero_api_client(
  zero zero: msg,
) -> Client(req, ws, ws_event, close_reason, model, msg) {
  Client(
    ws: no_ws_conn,
    reqs: req.empty_reqs(),
    reconnected: False,
    ws_url: "",
    impl: zero_impl(zero),
    set_client: fn(model, _) { model },
    wrap: fn(_) { zero },
    notify: fn(_) { None },
    send: fn(model, _) {
      io.println_error("WARNING `zero_api_client.send` called (actual client not yet initialized)")
      #(model, effect.none())
    },
    recv: fn(model, _) {
      io.println_error("WARNING `zero_api_client.recv` called (actual client not yet initialized)")
      #(model, effect.none())
    },
  )
}

fn zero_impl(
  zero zero: msg,
) -> WebSocketImpl(ws, ws_event, close_reason, msg) {
  WebSocketImpl(
    connect: fn(_, _) { effect.none() },
    send: fn(_, _) { effect.none() },
    wrap: fn(_) { zero },
    event: fn(_) { NoOp },
    send_after: fn(_, _) { effect.none() },
  )
}

pub type ApiData(t) {
  NotAsked
  Loading
  Failure(err: Err)
  Success(data: t)
}

pub fn success_or(
  data data: ApiData(a),
  default default: a,
) -> ApiData(a) {
  case data {
    Success(data:_) ->
      data

    NotAsked | Loading | Failure(err:_) ->
      Success(data: default)
  }
}

pub fn map_success(
  data data: ApiData(a),
  apply f: fn(a) -> b,
) -> ApiData(b) {
  case data {
    NotAsked -> NotAsked
    Loading -> Loading
    Failure(err:) -> Failure(err:)
    Success(data:) -> Success(data: f(data))
  }
}

// INIT

pub fn is_connected(
  client client: Client(req, ws, ws_event, close_reason, model, msg),
) -> Bool {
  result.is_ok(client.ws.ws)
}

pub fn init(
  model model: model,
  ws_url ws_url: String,
  //
  get_client get_client: fn(model) -> Client(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, Client(req, ws, ws_event, close_reason, model, msg)) -> model,
  wrap wrap: fn(Msg(ws, close_reason)) -> msg,
  notify notify: fn(ConnectionEvent) -> Option(msg),
  on_no_conn on_no_conn: fn(model) -> Option(msg), // TODO maybe rm and use `notify` instead?
  encode encode: fn(req) -> Json,
  //
  impl impl: WebSocketImpl(ws, ws_event, close_reason, msg),
) -> #(model, Effect(msg)) {
  let get_send: fn(model) -> Option(fn(String) -> Effect(msg)) = fn(model) {
    case get_client(model).ws {
      Conn(ws: Error(_)) -> None
      Conn(ws: Ok(ws)) -> Some(impl.send(_, ws))
    }
  }

  Client(
    ws: no_ws_conn,
    reqs: req.empty_reqs(),
    reconnected: False,
    //
    ws_url:,
    impl:,
    set_client:,
    wrap:,
    notify:,
    //
    send: fn(model, req) {
      send_model(model:, req:, get_client:, set_client:, get_send:, encode:, on_no_conn:)
    },
    recv: fn(model, json) {
      recv_model(model:, json:, get_client:, set_client:)
    },
  )
  |> set_client(model, _)
  |> pair.new(effect.batch([
    effect.from(fn(dispatch) {
      dispatch(impl.wrap(GotReconnectWebSocket(with_delay: False)))
    }),
  ]))
}

pub opaque type Conn(ws) {
  Conn(
    ws: Result(ws, Int)
  )
}

const no_ws_conn = Conn(ws: Error(0))

// SEND (INIT)

fn send_model(
  get_client get_client: fn(model) -> Client(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, Client(req, ws, ws_event, close_reason, model, msg)) -> model,
  get_send get_send: fn(model) -> Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
  on_no_conn handle_no_conn: fn(model) -> Option(msg),
  model model: model,
  req req: Req(req, msg),
) -> #(model, Effect(msg)) {
  let client = get_client(model)
  let send: Option(fn(String) -> Effect(msg)) = get_send(model)

  case req.send(req:, reqs: client.reqs, send:, encode:) {
    Ok(#(reqs, send_eff)) ->
      model
      |> set_client(Client(..client, reqs:))
      |> pair.new(send_eff)

    Error(NoConn) ->
      case handle_no_conn(model) {
        Some(msg) ->
          model
          |> pair.new(effect.from(fn(dispatch) {
            dispatch(msg)
          }))

        None ->
          #(model, effect.none())
      }
  }
}

// RECEIVE (INIT)

type PayloadType {
  Response
  Subscription
}

fn payload_type(
  dyn: Dynamic,
) -> #(PayloadType, Dynamic) {
  let decoder: Decoder(Result(types.SubscriptionMsg(Dynamic), err)) =
    types.decoder_subscription_msg(decode.dynamic)
    |> types.decoder_result_ok

  case decode.run(dyn, decoder) {
    Ok(Ok(types.S(dyn))) -> #(Subscription, dyn)
    _ -> #(Response, dyn)
  }
}

fn recv_model(
  get_client get_client: fn(model) -> Client(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, Client(req, ws, ws_event, close_reason, model, msg)) -> model,
  model model: model,
  json json: String,
) -> #(model, Effect(msg)) {
  let client = get_client(model)

  case recv_reqs(json:, reqs: client.reqs) {
    Ok(#(reqs, msg)) ->
      model
      |> set_client(Client(..client, reqs:))
      |> pair.new(effect.from(fn(dispatch) {
        dispatch(msg)
      }))

    Error(err) ->
      model
      |> set_client(Client(..client, reqs: {
        client.reqs
        |> clear_req_and_log_err(err:)
      }))
      |> pair.new(effect.none())
  }
}

fn recv_reqs(
  reqs reqs: Reqs(msg),
  json json: String,
) -> Result(#(Reqs(msg), msg), RecvErr) {
  use #(ref, dyn) <- result.try(recv_ref_and_dyn(json:))

  let #(typ, dyn) = payload_type(dyn)

  let get_handler =
    case typ {
      Subscription -> req.get_req
      Response -> req.pop_req
    }

  use #(reqs, handle_resp) <- result.try(
    get_handler(reqs, ref)
    |> result.replace_error(req.ReqNotFound(ref:, json:))
  )

  let req.HandlerResult(result:, err: to_err_msg) =
    handle_resp(dyn)

  let msg =
    case result {
      Ok(msg) -> msg
      Error(err) -> err |> to_err_msg
    }

  Ok(#(reqs, msg))
}

fn recv_ref_and_dyn(
  json json: String,
) -> Result(#(Uuid, Dynamic), RecvErr) {
  use ref <- result.try(
    decode.at(["ref"], decode.string)
    |> json.parse(json, _)
    |> result.replace_error(req.NoRef(json:))
  )

  use ref <- result.try(
    uuid.from_string(ref)
    |> result.map_error(fn(err) {
      req.RefParseFailure(ref:, err: err |> string.inspect)
    })
  )

  use resp <- result.try(
    decode.at(["result"], decode.dynamic)
    |> json.parse(json, _)
    |> result.replace_error(req.ResultNotFound(ref:, json:))
  )

  Ok(#(ref, resp))
}

// UPDATE

pub opaque type Msg(ws, close_reason) {
  NoOp
  RecvWebSocketInvalidUrlErr
  RecvWebSocketBinaryMessage(msg: BitArray)
  RecvWebSocketTextMessage(msg: String)
  RecvWebSocketOpen(ws: ws)
  RecvWebSocketClose(reason: close_reason)
  GotReconnectWebSocket(with_delay: Bool)
}

pub const invalid_url = RecvWebSocketInvalidUrlErr
pub const ws_binary_message = RecvWebSocketBinaryMessage
pub const ws_text_message = RecvWebSocketTextMessage
pub const ws_open = RecvWebSocketOpen
pub const ws_close = RecvWebSocketClose

pub type ConnectionEvent {
  Connected(reconnect: Bool)
  Disconnected
  WebSocketUrlInvalid
}

pub fn update(
  model model: model,
  msg msg: Msg(ws, close_reason),
  client client: Client(api, ws, ws_event, close_reason, model, parent_msg),
) -> #(model, Effect(parent_msg)) {
  let map_parent = fn(t: #(Client(api, ws, ws_event, close_reason, model, parent_msg), Effect(Msg(ws, close_reason)))) {
    model
    |> client.set_client(t.0)
    |> pair.new(effect.batch([
      t.1 |> effect.map(client.wrap),
    ]))
  }

  // let client = get_client(model)

  case msg {
    NoOp ->
      pure(model)

    RecvWebSocketBinaryMessage(msg: ba) ->
      ignore_binary_msg(model:, ba:)

    RecvWebSocketTextMessage(msg:) ->
      client.recv(model, msg)

    RecvWebSocketInvalidUrlErr ->
      notify_invalid_url(model:, client:)

    RecvWebSocketOpen(ws:) ->
      set_websocket_conn(model:, client:, ws:)

    RecvWebSocketClose(reason:) ->
      reconnect_to_websocket_on_close(model:, client:, reason:)

    GotReconnectWebSocket(with_delay:) ->
      client
      |> attempt_reconnect_to_websocket(with_delay:)
      |> pair.map_first(client.set_client(model, _))
  }
}

fn set_websocket_conn(
  model model,
  client client: Client(api, ws, ws_event, close_reason, model, parent_msg),
  ws ws: ws,
) -> #(model, Effect(parent_msg)) {
  let reconnect = client.reconnected

  let type_ =
    case reconnect {
      True -> "reconnect"
      False -> "initial connect"
    }

  io.println("WebSocket opened: `" <> client.ws_url <> "` (" <> type_ <> ")")

  model
  |> client.set_client(Client(..client, reconnected: True, ws: Conn(ws: Ok(ws))))
  |> pair.new(effect.batch([
    Connected(reconnect:)
    |> client.notify // TODO duped notify
    |> option.map(fn(msg) {
      effect.from(fn(dispatch) { dispatch(msg) })
    })
    |> option.unwrap(effect.none())
  ]))
}

fn reconnect_to_websocket_on_close(
  model model: model,
  client client: Client(api, ws, ws_event, close_reason, model, parent_msg),
  reason reason: close_reason,
) -> #(model, Effect(parent_msg)) {
  io.println_error("WebSocket closed: " <> reason |> string.inspect)

  let ws =
    case client.ws {
      Conn(ws: Ok(_)) -> Conn(ws: Error(0))
      Conn(ws: Error(attempt)) -> Conn(ws: Error(attempt + 1))
    }

  Client(..client, ws:)
  |> eff([
    effect.from(fn(dispatch) {
      dispatch(GotReconnectWebSocket(with_delay: True))
    }),
  ])
  |> pair.map_first(client.set_client(model, _))
  |> pair.map_second(effect.map(_, client.wrap))
}

const base_delay_ms = 1_000 // 1s
const max_delay_ms = 60_000 // 60s

fn attempt_reconnect_to_websocket(
  client client: Client(api, ws, ws_event, close_reason, model, parent_msg),
  with_delay delay: Bool,
) -> #(Client(api, ws, ws_event, close_reason, model, parent_msg), Effect(parent_msg)) {
  case client.ws, delay {
    Conn(ws: Ok(_conn)), _ ->
      pure(client)

    Conn(ws: Error(attempt)), True -> {
      client
      |> pair.new(effect.batch([
        client.impl.send_after(
          exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
          client.impl.wrap(GotReconnectWebSocket(with_delay: False)),
        ),
      ]))
    }

    Conn(ws: Error(_attempt)), False -> {
      client
      |> pair.new(effect.batch([
        client.impl.connect(client.ws_url, client.impl.event) |> effect.map(client.impl.wrap),
      ]))
    }
  }
}

fn ignore_binary_msg(
  model model: model,
  ba ba: BitArray,
) -> #(model, Effect(parent_msg)) {
  io.println_error("Ignoring WebSocket binary msg: " <> ba |> string.inspect)
  pure(model)
}

fn notify_invalid_url(
  model model: model,
  client client: Client(api, ws, ws_event, close_reason, model, parent_msg),
) -> #(model, Effect(parent_msg)) {
  io.println_error("Invalid URL: " <> client.ws_url)

  model
  |> pair.new(effect.batch([
    WebSocketUrlInvalid
    |> client.notify // TODO duped notify
    |> option.map(fn(msg) {
      effect.from(fn(dispatch) { dispatch(msg) })
    })
    |> option.unwrap(effect.none())
  ]))
}

// helpers

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
