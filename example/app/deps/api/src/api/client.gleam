import api
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

pub type Err {
  ApiErr(err: api.Err)
  RecvErr(err: RecvErr)
}

pub type RecvErr {
  NoRef(
    json: String,
  )
  RefParseFailure(
    ref: String,
    err: String,
  )
  ReqNotFound(
    ref: Uuid,
    json: String,
  )
  ResultNotFound(
    ref: Uuid,
    json: String,
  )
  // JsonDecodeErr(
  //   ref: Uuid,
  //   err: json.DecodeError,
  // )
  DecodeErrs(
    ref: Uuid,
    errs: List(decode.DecodeError),
  )
}

pub opaque type Reqs(msg) {
  Reqs(
    dict: Dict(Uuid, HandlerFunc(msg)),
  )
}

pub type HandlerFunc(msg) = fn(Dynamic) -> HandlerResult(msg)

pub opaque type HandlerResult(msg) {
  HandlerResult(
    result: Result(msg, RecvErr),
    err: fn(RecvErr) -> msg,
  )
}

pub type NoConn {
  NoConn
}

//

pub type ApiClient(req, model, msg) {
  ApiClient(
    reqs: Reqs(msg),
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

pub fn init(
  get_client get_client: fn(model) -> ApiClient(req, model, msg),
  set_client set_client: fn(model, ApiClient(req, model, msg)) -> model,
  get_send get_send: fn(model) -> Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
  on_no_conn handle_no_conn: fn(model) -> Option(msg),
) -> ApiClient(req, model, msg) {
  let send =
    fn(model, req) {
      let client = get_client(model)
      let send = get_send(model)

      case send_(req:, reqs: client.reqs, send:, encode:) {
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

  let sub =
    fn(model, req) {
      let client = get_client(model)
      let send = get_send(model)

      case send_(req:, reqs: client.reqs, send:, encode:) {
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

  let recv =
    fn(model, json) {
      let client = get_client(model)
      case recv(json:, reqs: client.reqs) {
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

  ApiClient(reqs: Reqs(dict: dict.new()), send:, recv:)
}

// RECEIVE

fn recv(
  reqs reqs: Reqs(msg),
  json json: String,
) -> Result(#(Reqs(msg), msg), RecvErr) {
  use #(ref, dyn) <- result.try(recv_ref_and_dyn(json:))

  use #(reqs, handle_resp) <- result.try(
    pop_req(reqs, ref)
    |> result.replace_error(ReqNotFound(ref:, json:))
  )

  let HandlerResult(result:, err: to_err_msg) =
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
    |> result.replace_error(NoRef(json:))
  )

  use ref <- result.try(
    uuid.from_string(ref)
    |> result.map_error(fn(err) {
      RefParseFailure(ref:, err: err |> string.inspect)
    })
  )

  use resp <- result.try(
    decode.at(["result"], decode.dynamic)
    |> json.parse(json, _)
    |> result.replace_error(ResultNotFound(ref:, json:))
  )

  Ok(#(ref, resp))
}

fn pop_req(
  reqs reqs: Reqs(msg),
  ref ref: Uuid,
) -> Result(#(Reqs(msg), HandlerFunc(msg)), Nil) {
  use f <- result.try(dict.get(reqs.dict, ref))

  let reqs = Reqs(dict: dict.delete(reqs.dict, ref))

  Ok(#(reqs, f))
}

fn insert_req(
  reqs reqs: Reqs(msg),
  ref ref: Uuid,
  handler handler: HandlerFunc(msg),
) -> Reqs(msg) {
  Reqs(dict: reqs.dict |> dict.insert(ref, handler))
}

fn clear_req_and_log_err(
  reqs reqs: Reqs(msg),
  err err: RecvErr,
) -> Reqs(msg) {
  io.println_error("`RecvErr`:\n" <> err |> string.inspect)

  case err {
    NoRef(..) |
    RefParseFailure(..) ->
      reqs

    ReqNotFound(ref:, ..) |
    ResultNotFound(ref:, ..) |
    DecodeErrs(ref:, ..) ->
    // JsonDecodeErr(ref:, ..) ->
      case pop_req(reqs, ref) {
        Error(Nil) ->
          reqs

        Ok(#(reqs, _req)) ->
          reqs
      }
  }
}

// SEND

pub opaque type Req(req, msg) {
  Req(
    ref: Uuid,
    req: req,
    resp: HandlerFunc(msg),
  )
}

fn send_(
  reqs reqs: Reqs(msg),
  req req: Req(req, msg),
  send send: Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
) -> Result(#(Reqs(msg), Effect(msg)), NoConn) {
  case send {
    None ->
      Error(NoConn)

    Some(send) -> {
      let reqs = insert_req(reqs, req.ref, req.resp)

      let send_eff =
        req.req
        |> SocketReq(ref: req.ref)
        |> generic.encode_socket_req(encode)
        |> json.to_string
        |> send

      Ok(#(reqs, send_eff))
    }
  }
}

//

fn func(
  req req: fn(Func(param, return)) -> req,
  param param: param,
  decoder decoder: Decoder(return),
  msg msg: fn(Result(return, Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Func(FuncReq(param:)))
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn sub(
  sub sub: Sub(sub_msg),
  req req: fn(Sub(sub_msg)) -> req,
  msg msg: fn(Result(Nil, Err)) -> msg,
) -> Req(req, msg) {
  let req = req(sub)
  let err = fn(err) { msg(Error(RecvErr(err))) }
  let decoder = generic.decoder_nil()
  build_req(req:, decoder:, msg:, err:)
}

fn list(
  req req: fn(Crud(t, create, update, key)) -> req,
  params params: Option(Params(key)),
  decoder decoder: Decoder(Paginated(t)),
  msg msg: fn(Result(Paginated(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(List(ListReq(params:)))
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn read(
  req req: fn(Crud(t, create, update, key)) -> req,
  id id: Id(t),
  decoder decoder: Decoder(t),
  msg msg: fn(Result(Record(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Read(ReadReq(id:)))
  let decoder = decoder_record(decoder)
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn create(
  req req: fn(Crud(t, create, update, key)) -> req,
  data data: create,
  decoder decoder: Decoder(t),
  msg msg: fn(Result(Record(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Create(CreateReq(data:)))
  let decoder = decoder_record(decoder)
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn update(
  req req: fn(Crud(t, create, update, key)) -> req,
  id id: Id(t),
  data data: update,
  decoder decoder: Decoder(t),
  msg msg: fn(Result(Record(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Update(UpdateReq(id:, data:)))
  let decoder = decoder_record(decoder)
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn delete(
  req req: fn(Crud(t, create, update, key)) -> req,
  id id: Id(t),
  confirm confirm: ConfirmDelete,
  decoder decoder: Decoder(t),
  msg msg: fn(Result(Record(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Delete(DeleteReq(id:, confirm:)))
  let decoder = decoder_record(decoder)
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

fn build_req(
  req req: req,
  decoder decoder: Decoder(t),
  msg msg: fn(Result(t, Err)) -> msg,
  err err: fn(RecvErr) -> msg
) -> Req(req, msg) {
  let ref = uuid.v7()
  Req(ref:, req:, resp: fn(dyn) {
    dyn
    |> decode.run(generic.decoder_result(decoder, generic.decoder_err()))
    |> result.map(result.map_error(_, ApiErr))
    |> result.map(msg)
    |> result.map_error(DecodeErrs(ref:, errs: _))
    |> HandlerResult(result: _, err:)
  })
}

const paginated = generic.decoder_paginated

fn action(
  msg msg: fn(#(Action, Result(Record(t), Err))) -> msg,
  action action: Action,
) -> fn(Result(Record(t), Err)) -> msg {
  fn(result) { msg(#(action, result)) }
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
  msg msg: fn(Result(Nil, Err)) -> msg,
) -> Req(Api, msg) {
  sub(Sub, SubscribeToItems, msg)
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
  list(Items, params, paginated(decoder_item()), msg)
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
  create(Items, data, decoder_item(), msg |> action(Created))
}

pub fn req_update_items(
  id id: Id(Item),
  data data: Item,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  update(Items, id, data, decoder_item(), msg |> action(Updated))
}

pub fn req_delete_items(
  id id: Id(Item),
  confirm confirm: ConfirmDelete,
  msg msg: fn(#(Action, Result(Record(Item), Err))) -> msg,
) -> Req(Api, msg) {
  delete(Items, id, confirm, decoder_item(), msg |> action(Deleted))
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
