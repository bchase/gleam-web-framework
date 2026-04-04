import gleam/float
import gleam/int
import api
import api/client/req.{type RecvErr, type Req, type Reqs, NoConn, clear_req_and_log_err, create, delete, func, list, read, update}
import api/generic.{type Action, type ConfirmDelete, type Crud, type Func, type Paginated, type Pagination, type Params, type Record, type SocketReq, type Sub, Create, CreateReq, Created, Delete, DeleteReq, Deleted, Func, FuncReq, List, ListReq, Read, ReadReq, SocketReq, Sub, Update, UpdateReq, Updated, decoder_action, decoder_crud, decoder_func, decoder_record, decoder_sub, encode_action, encode_crud, encode_func, encode_record, encode_sub}
import api/id.{type Id}
import deriv/util as deriv
import gleam/dict.{type Dict}
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

pub type WebSocketImpl(ws, ws_event, msg) {
  WebSocketImpl(
    connect: fn(String, fn(ws_event) -> ConnMsg(ws, ws_event)) -> Effect(ConnMsg(ws, ws_event)),
    wrap: fn(ConnMsg(ws, ws_event)) -> msg,
    event: fn(ws_event) -> ConnMsg(ws, ws_event),
    //
    send_after: fn(Int, msg) -> Effect(msg),
  )
}

pub type ApiClient(req, ws, ws_event, close_reason, model, msg) {
  ApiClient(
    //
    ws: Result(ws, Int),
    reqs: Reqs(msg),
    // static
    ws_url: String,
    impl: WebSocketImpl(ws, ws_event, msg),
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

pub fn send(
  get_client get_client: fn(model) -> ApiClient(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, ApiClient(req, ws, ws_event, close_reason, model, msg)) -> model,
  get_send get_send: fn(model) -> Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
  on_no_conn handle_no_conn: fn(model) -> Option(msg),
  model model: model,
  req req: Req(req, msg),
) -> #(model, Effect(msg)) {
  let client = get_client(model)
  let send = get_send(model)

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

pub fn init(
  model model: model,
  ws_url ws_url: String,
  //
  get_client get_client: fn(model) -> ApiClient(req, ws, ws_event, close_reason, model, msg),
  set_client set_client: fn(model, ApiClient(req, ws, ws_event, close_reason, model, msg)) -> model,
  get_send get_send: fn(model) -> Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
  notify notify: fn(ConnectionEvent) -> Option(msg),
  on_no_conn on_no_conn: fn(model) -> Option(msg), // TODO rm and use `notify` instead
  //
  impl impl: WebSocketImpl(ws, ws_event, msg),
) -> #(model, Effect(msg)) {
  ApiClient(
    ws: no_ws_conn,
    reqs: req.empty_reqs(),
    //
    ws_url:,
    impl:,
    notify:,
    // pub "methods"
    send: fn(model, req) {
      send(model:, req:, get_client:, set_client:, get_send:, encode:, on_no_conn:)
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

const no_ws_conn = Error(0)

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

// dummy api

pub type Api {
  //$ derive json encode decode
  Items(crud: Crud(Item, Item, Item, ItemAttr))
  IntToString(func: Func(Int, String))
  SubscribeToItems(sub: Sub(ItemsSubMsg))
}

//pub type ApiSub {
//  //$ derive json encode decode
//  ItemsSub
//}
pub type ItemsSubMsg {
  //$ derive json encode decode
  ItemsSubMsg(action: Action, item: Record(Item))
}

pub type Item {
  //$ derive json encode decode
  Item(
    name: String,
  )
}

pub type ItemAttr {
  //$ derive json encode decode
  ItemName
}

// codegen helpers

pub fn req_subscribe_to_items(
  msg msg: fn(Result(ItemsSubMsg, Err)) -> msg,
) -> Req(Api, msg) {
  req.sub(Sub, SubscribeToItems, decoder_items_sub_msg(),  msg)
}

pub fn req_int_to_string(
  param param: Int,
  msg msg: fn(Result(String, Err)) -> msg,
) -> Req(Api, msg) {
  func(IntToString, param, decode.string, msg)
}

pub fn req_list_items(
  params params: Option(Params(ItemAttr)),
  msg msg: fn(Result(Paginated(Item), Err)) -> msg,
) -> Req(Api, msg) {
  list(Items, params, req.paginated(decoder_item()), msg)
}

pub fn req_read_items(
  id id: Id(Item),
  msg msg: fn(Result(Record(Item), Err)) -> msg,
) -> Req(Api, msg) {
  read(Items, id, decoder_item(), msg)
}

pub fn req_create_items(
  data data: Item,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  create(Items, data, decoder_item(), msg |> req.action(Created))
}

pub fn req_update_items(
  id id: Id(Item),
  data data: Item,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  update(Items, id, data, decoder_item(), msg |> req.action(Updated))
}

pub fn req_delete_items(
  id id: Id(Item),
  confirm confirm: ConfirmDelete,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  delete(Items, id, confirm, decoder_item(), msg |> req.action(Deleted))
}

// DERIVED

pub fn encode_api(value: Api) -> Json {
  case value {
    Items(..) as value ->
      json.object([
        #("_var", json.string("Items")),
        #(
          "crud",
          encode_crud(
            value.crud,
            encode_item,
            encode_item,
            encode_item,
            encode_item_attr,
          ),
        ),
      ])
    IntToString(..) as value ->
      json.object([
        #("_var", json.string("IntToString")),
        #("func", encode_func(value.func, json.int, json.string)),
      ])
    SubscribeToItems(..) as value ->
      json.object([
        #("_var", json.string("SubscribeToItems")),
        #("sub", encode_sub(value.sub, encode_items_sub_msg)),
      ])
  }
}

pub fn decoder_api() -> Decoder(Api) {
  decode.one_of(decoder_api_items(), [
    decoder_api_int_to_string(),
    decoder_api_subscribe_to_items(),
  ])
}

pub fn decoder_api_items() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("Items"))
  use crud <- decode.field(
    "crud",
    decoder_crud(
      decoder_item(),
      decoder_item(),
      decoder_item(),
      decoder_item_attr(),
    ),
  )
  decode.success(Items(crud:))
}

pub fn decoder_api_int_to_string() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("IntToString"))
  use func <- decode.field("func", decoder_func(decode.int, decode.string))
  decode.success(IntToString(func:))
}

pub fn encode_items_sub_msg(value: ItemsSubMsg) -> Json {
  case value {
    ItemsSubMsg(..) as value ->
      json.object([
        #("action", encode_action(value.action)),
        #("item", encode_record(value.item, encode_item)),
      ])
  }
}

pub fn decoder_items_sub_msg() -> Decoder(ItemsSubMsg) {
  decode.one_of(decoder_items_sub_msg_items_sub_msg(), [])
}

pub fn decoder_items_sub_msg_items_sub_msg() -> Decoder(ItemsSubMsg) {
  use action <- decode.field("action", decoder_action())
  use item <- decode.field("item", decoder_record(decoder_item()))
  decode.success(ItemsSubMsg(action:, item:))
}

pub fn encode_item(value: Item) -> Json {
  case value {
    Item(..) as value -> json.object([#("name", json.string(value.name))])
  }
}

pub fn decoder_item() -> Decoder(Item) {
  decode.one_of(decoder_item_item(), [])
}

pub fn decoder_item_item() -> Decoder(Item) {
  use name <- decode.field("name", decode.string)
  decode.success(Item(name:))
}

pub fn encode_item_attr(value: ItemAttr) -> Json {
  case value {
    ItemName -> json.object([])
  }
}

pub fn decoder_item_attr() -> Decoder(ItemAttr) {
  decode.one_of(decoder_item_attr_item_name(), [])
}

pub fn decoder_item_attr_item_name() -> Decoder(ItemAttr) {
  decode.success(ItemName)
}


pub fn decoder_api_subscribe_to_items() -> Decoder(Api) {
  use _deriv_var_constr <- decode.field("_var", deriv.is("SubscribeToItems"))
  use sub <- decode.field("sub", decoder_sub(decoder_items_sub_msg()))
  decode.success(SubscribeToItems(sub:))
}

//

pub opaque type ConnMsg(ws, close_reason) {
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

pub fn update_(
  model model: model,
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  // get_client get_client: fn(model) -> ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  wrap to_parent_msg: fn(ConnMsg(ws, close_reason)) -> parent_msg,
  msg msg: ConnMsg(ws, close_reason),
  set_conn set_conn: fn(model, ApiClient(api, ws, ws_event, close_reason, model, parent_msg)) -> model,
) -> #(model, Effect(parent_msg)) {
  let map_parent = fn(t: #(ApiClient(api, ws, ws_event, close_reason, model, parent_msg), Effect(ConnMsg(ws, close_reason)))) {
    model
    |> set_conn(t.0)
    |> pair.new(effect.batch([
      t.1 |> effect.map(to_parent_msg),
    ]))
  }

  // let client = get_client(model)

  case msg {
    RecvWebSocketBinaryMessage(msg: ba) ->
      ignore_binary_msg(model:, ba:)

    RecvWebSocketTextMessage(msg:) ->
      client.recv(model, msg)

    RecvWebSocketInvalidUrlErr ->
      notify_invalid_url(model:, client:)

    RecvWebSocketOpen(ws:) ->
      set_websocket_conn(model:, client:, ws:, set_conn:)

    RecvWebSocketClose(reason:) ->
      reconnect_to_websocket_on_close(client:, reason:) |> map_parent

    GotReconnectWebSocket(with_delay:) ->
      client
      |> attempt_reconnect_to_websocket(with_delay:)
      |> pair.map_first(set_conn(model, _))
  }
}

fn set_websocket_conn(
  model model,
  client client: ApiClient(api, ws, ws_event, close_reason, model, parent_msg),
  ws ws: ws,
  set_conn set_conn: fn(model, ApiClient(api, ws, ws_event, close_reason, model, parent_msg)) -> model,
) -> #(model, Effect(parent_msg)) {
  io.println("WebSocket opened: " <> client.ws_url)

  model
  |> set_conn(ApiClient(..client, ws: Ok(ws)))
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
      Ok(_conn) -> Error(0)
      Error(attempt) -> Error(attempt + 1)
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
    Ok(_conn), _ ->
      pure(client)

    Error(attempt), True -> {
      ApiClient(..client, ws: Error(attempt))
      |> pair.new(effect.batch([
        client.impl.send_after(
          exp_backoff_delay_ms(attempt:, base_delay_ms:, max_delay_ms:),
          client.impl.wrap(GotReconnectWebSocket(with_delay: False)),
        ),
      ]))
    }

    Error(_attempt), False -> {
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
