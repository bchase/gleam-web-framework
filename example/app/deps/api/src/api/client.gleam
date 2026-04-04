import gleam/float
import gleam/int
import api/client/req.{type RecvErr, type Req, type Reqs, NoConn, clear_req_and_log_err}
import api/generic
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

pub type WebSocketImpl(ws, ws_event, close_reason, msg) {
  WebSocketImpl(
    connect: fn(String, fn(ws_event) -> ConnMsg(ws, close_reason)) -> Effect(ConnMsg(ws, close_reason)),
    send: fn(String, ws) -> Effect(msg),
    wrap: fn(ConnMsg(ws, close_reason)) -> msg,
    event: fn(ws_event) -> ConnMsg(ws, close_reason),
    //
    send_after: fn(Int, msg) -> Effect(msg),
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

pub fn zero_api_client(
  zero zero: msg,
) -> ApiClient(req, ws, ws_event, close_reason, model, msg) {
  ApiClient(
    ws: no_ws_conn,
    reqs: req.empty_reqs(),
    ws_url: "",
    impl: zero_impl(zero),
    notify: fn(_) { None },
    send: fn(model, _) { #(model, effect.none()) },
    recv: fn(model, _) { #(model, effect.none()) },
  )
}

pub type ApiClient(req, ws, ws_event, close_reason, model, msg) {
  ApiClient(
    //
    ws: Conn(ws),
    reqs: Reqs(msg),
    // static
    ws_url: String,
    impl: WebSocketImpl(ws, ws_event, close_reason, msg),
    notify: fn(ConnectionEvent) -> Option(msg),
    // public "methods"
    send: fn(model, Req(req, msg)) -> #(model, Effect(msg)),
    recv: fn(model, String) -> #(model, Effect(msg)),
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

//

pub fn init(
  model model: model,
  ws_url ws_url: String,
  //
  get_client get_client: fn(model) -> ApiClient(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, ApiClient(req, ws, ws_event, close_reason, model, msg)) -> model,
  encode encode: fn(req) -> Json,
  notify notify: fn(ConnectionEvent) -> Option(msg),
  on_no_conn on_no_conn: fn(model) -> Option(msg), // TODO maybe rm and use `notify` instead?
  //
  impl impl: WebSocketImpl(ws, ws_event, close_reason, msg),
) -> #(model, Effect(msg)) {
  let get_send: fn(model) -> Option(fn(String) -> Effect(msg)) = fn(model) {
    case get_client(model).ws {
      Conn(ws: Error(_)) -> None
      Conn(ws: Ok(ws)) -> Some(impl.send(_, ws))
    }
  }

  ApiClient(
    ws: no_ws_conn,
    reqs: req.empty_reqs(),
    //
    ws_url:,
    impl:,
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

// SEND

fn send_model(
  get_client get_client: fn(model) -> ApiClient(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, ApiClient(req, ws, ws_event, close_reason, model, msg)) -> model,
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
      |> set_client(ApiClient(..client, reqs:))
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

// RECEIVE

type PayloadType {
  Response
  Subscription
}

fn payload_type(
  dyn: Dynamic,
) -> #(PayloadType, Dynamic) {
  let decoder: Decoder(Result(generic.SubscriptionMsg(Dynamic), err)) =
    generic.decoder_subscription_msg(decode.dynamic)
    |> generic.decoder_result_ok

  case decode.run(dyn, decoder) {
    Ok(Ok(generic.S(dyn))) -> #(Subscription, dyn)
    _ -> #(Response, dyn)
  }
}

fn recv_model(
  get_client get_client: fn(model) -> ApiClient(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, ApiClient(req, ws, ws_event, close_reason, model, msg)) -> model,
  model model: model,
  json json: String,
) -> #(model, Effect(msg)) {
  let client = get_client(model)

  case recv_reqs(json:, reqs: client.reqs) {
    Ok(#(reqs, msg)) ->
      model
      |> set_client(ApiClient(..client, reqs:))
      |> pair.new(effect.from(fn(dispatch) {
        dispatch(msg)
      }))

    Error(err) ->
      model
      |> set_client(ApiClient(..client, reqs: {
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

//

pub opaque type ConnMsg(ws, close_reason) {
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
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  // get_client get_client: fn(model) -> ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  wrap to_parent_msg: fn(ConnMsg(ws, close_reason)) -> parent_msg,
  msg msg: ConnMsg(ws, close_reason),
  set_client set_client: fn(model, ApiClient(api, ws, ws_event, close_reason, model, parent_msg)) -> model,
) -> #(model, Effect(parent_msg)) {
  let map_parent = fn(t: #(ApiClient(api, ws, ws_event, close_reason, model, parent_msg), Effect(ConnMsg(ws, close_reason)))) {
    model
    |> set_client(t.0)
    |> pair.new(effect.batch([
      t.1 |> effect.map(to_parent_msg),
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
      set_websocket_conn(model:, client:, ws:, set_client:)

    RecvWebSocketClose(reason:) ->
      reconnect_to_websocket_on_close(client:, reason:) |> map_parent

    GotReconnectWebSocket(with_delay:) ->
      client
      |> attempt_reconnect_to_websocket(with_delay:)
      |> pair.map_first(set_client(model, _))
  }
}

fn set_websocket_conn(
  model model,
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  ws ws: ws,
  set_client set_client: fn(model, ApiClient(api, ws, ws_event, close_reason, model, parent_msg)) -> model,
) -> #(model, Effect(parent_msg)) {
  io.println("WebSocket opened: " <> client.ws_url)

  model
  |> set_client(ApiClient(..client, ws: Conn(ws: Ok(ws))))
  |> pair.new(effect.batch([
    Connected(reconnect: False)
    |> client.notify // TODO duped notify
    |> option.map(fn(msg) {
      effect.from(fn(dispatch) { dispatch(msg) })
    })
    |> option.unwrap(effect.none())
  ]))
}

fn reconnect_to_websocket_on_close(
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  reason reason: close_reason,
) -> #(ApiClient(api, ws, ws_event, close_reason, model, parent_msg), Effect(ConnMsg(ws, close_reason))) {
  io.println_error("WebSocket closed: " <> reason |> string.inspect)

  let ws =
    case client.ws {
      Conn(ws: Ok(_)) -> Conn(ws: Error(0))
      Conn(ws: Error(attempt)) -> Conn(ws: Error(attempt + 1))
    }

  ApiClient(..client, ws:)
  |> eff([
    effect.from(fn(dispatch) {
      dispatch(GotReconnectWebSocket(with_delay: True))
    }),
  ])
}

const base_delay_ms = 1_000 // 1s
const max_delay_ms = 60_000 // 60s

fn attempt_reconnect_to_websocket(
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  with_delay delay: Bool,
) -> #(ApiClient(api, ws, ws_event, close_reason, model, parent_msg), Effect(parent_msg)) {
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
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
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
