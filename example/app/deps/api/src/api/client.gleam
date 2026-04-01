import api
import api/generic.{type ConfirmDelete, type Crud, type Func, type Paginated, type Pagination, type Params, type Record, type SocketReq, Create, CreateReq, Delete, DeleteReq, Func, FuncReq, List, ListReq, Read, ReadReq, SocketReq, Update, UpdateReq, decoder_crud, decoder_func, decoder_record, encode_crud, encode_func}
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
  Failure(err: RecvErr)
  Success(data: t)
}

pub fn init(
  get_client get_client: fn(model) -> ApiClient(req, model, msg),
  set_client set_client: fn(model, ApiClient(req, model, msg)) -> model,
  get_send get_send: fn(model) -> Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
  on_no_conn handle_no_conn: fn(NoConn) -> Option(msg),
) -> ApiClient(req, model, msg) {
  let send =
    fn(model, req) {
      let client = get_client(model)
      let send = get_send(model)

      case generic_send(req:, reqs: client.reqs, send:, encode:) {
        Ok(#(reqs, send_eff)) ->
          model
          |> set_client(ApiClient(..client, reqs:))
          |> pair.new(send_eff)

        Error(no_conn) ->
          case handle_no_conn(no_conn) {
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
      case generic_recv(json:, reqs: client.reqs) {
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

fn generic_recv(
  reqs reqs: Reqs(msg),
  json json: String,
) -> Result(#(Reqs(msg), msg), RecvErr) {
  use #(ref, resp) <- result.try(recv_(json:))

  use #(reqs, handle_resp) <- result.try(
    pop_req(reqs, ref)
    |> result.replace_error(ReqNotFound(ref:, json:))
  )

  let HandlerResult(result:, err: to_err_msg) =
    handle_resp(resp)

  let msg =
    case result {
      Ok(msg) -> msg
      Error(err) -> err |> to_err_msg
    }

  Ok(#(reqs, msg))
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

fn recv_(
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

// SEND

pub type Req(req, msg) {
  Req(
    ref: Uuid,
    req: req,
    resp: HandlerFunc(msg),
  )
}

fn generic_send(
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

// dummy lustre app

type Model {
  Model(
    conn: Option(Conn),
    client: ApiClient(Api, Model, Msg),
    //
    items: ApiData(List(Record(Item))),
  )
}

type Msg {
  NoOp
  GotItems(result: Result(Paginated(Item), RecvErr))
}

type Conn {
  Conn
}

fn emulate_ws_send(
  conn conn: Conn,
  msg msg: String,
) -> Nil {
  io.println("EMULATING WS SEND: " <> msg)
}

fn dummy_model(
) -> Model {
  let client =
    init(
      get_client: fn(model: Model) { model.client },
      set_client: fn(model: Model, client) { Model(..model, client:) },
      get_send: fn(model: Model) {
        case model.conn {
          None -> None
          // Some(conn) -> Some(emulate_ws_send(conn, _))
          Some(conn) -> todo
        }
      },
      encode: encode_api,
      on_no_conn: todo,
    )

  Model(
    conn: None,
    client:,
    //
    items: NotAsked,
  )
}

fn dummy_update(
  model model: Model,
  msg msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    NoOp ->
      todo

    GotItems(result:) ->
      case result {
        Ok(data) ->
          Model(..model, items: Success(data: data.resources))
          |> pair.new(effect.none())

        Error(_) ->
          todo
      }
  }
}

// dummy api

pub type Api {
  //$ derive json encode decode
  // Items(crud: Crud(Item, Item, Item, ItemAttr))
  IntToString(func: Func(Int, String))
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

type Transcoders(t) {
  Transcoders(
    decoder: fn() -> Decoder(t),
    encode: fn(t) -> Json,
  )
}

fn func(
  param param: param,
  msg to_msg: fn(Result(return, Err)) -> msg,
  //
  req req: fn(Func(param, return)) -> req,
  decoder decoder: Decoder(return),
) -> Req(req, msg) {
  let req = req(Func(FuncReq(param:)))
  let msg = fn(x) { to_msg(x) }
  let err = fn(err) { to_msg(Error(RecvErr(err))) }
  // build_req(req:, decoder:, msg:, err:)
  build_req(req:, decoder:, msg:, err:)
}

// fn list(
//   params params: Option(Params(key)),
//   msg to_msg: fn(Result(Paginated(t), RecvErr)) -> msg,
//   //
//   req req: fn(Crud(t, create, update, key)) -> req,
//   decoder decoder: Decoder(Paginated(t)),
// ) -> Req(req, msg) {
//   let req = req(List(ListReq(params:)))
//   let msg = fn(x) { to_msg(Ok(x)) }
//   let err = fn(err) { to_msg(Error(err)) }
//   build_req(req:, decoder:, msg:, err:)
// }

// fn read(
//   id id: Id(t),
//   msg to_msg: fn(Result(Record(t), RecvErr)) -> msg,
//   //
//   req req: fn(Crud(t, create, update, key)) -> req,
//   decoder decoder: Decoder(t),
// ) -> Req(req, msg) {
//   let req = req(Read(ReadReq(id:)))
//   let decoder = decoder_record(decoder)
//   let msg = fn(x) { to_msg(Ok(x)) }
//   let err = fn(err) { to_msg(Error(err)) }
//   build_req(req:, decoder:, msg:, err:)
// }

// fn create(
//   data data: create,
//   msg to_msg: fn(Result(Record(t), RecvErr)) -> msg,
//   //
//   req req: fn(Crud(t, create, update, key)) -> req,
//   decoder decoder: Decoder(t),
// ) -> Req(req, msg) {
//   let req = req(Create(CreateReq(data:)))
//   let decoder = decoder_record(decoder)
//   let msg = fn(x) { to_msg(Ok(x)) }
//   let err = fn(err) { to_msg(Error(err)) }
//   build_req(req:, decoder:, msg:, err:)
// }

// fn update(
//   id id: Id(t),
//   data data: update,
//   msg to_msg: fn(Result(Record(t), RecvErr)) -> msg,
//   //
//   req req: fn(Crud(t, create, update, key)) -> req,
//   decoder decoder: Decoder(t),
// ) -> Req(req, msg) {
//   let req = req(Update(UpdateReq(id:, data:)))
//   let decoder = decoder_record(decoder)
//   let msg = fn(x) { to_msg(Ok(x)) }
//   let err = fn(err) { to_msg(Error(err)) }
//   build_req(req:, decoder:, msg:, err:)
// }

// fn delete(
//   id id: Id(t),
//   confirm confirm: ConfirmDelete,
//   msg to_msg: fn(Result(Record(t), RecvErr)) -> msg,
//   //
//   req req: fn(Crud(t, create, update, key)) -> req,
//   decoder decoder: Decoder(t),
// ) -> Req(req, msg) {
//   let req = req(Delete(DeleteReq(id:, confirm:)))
//   let decoder = decoder_record(decoder)
//   let msg = fn(x) { to_msg(Ok(x)) }
//   let err = fn(err) { to_msg(Error(err)) }
//   build_req(req:, decoder:, msg:, err:)
// }

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
    // dyn
    // |> decode.run(generic.decoder_result(decoder, generic.decoder_err()))
    // |> result.map(result.map(_, fn(x) { msg(Ok(x))}))
    // |> result.map(result.map_error(_, ApiErr))
    // |> result.map_error(DecodeErrs(ref:, errs: _))
    // |> result.map_error(RecvErr)
    // |> result.flatten
    // |> HandlerResult(result: _, err:)
}

// codegen helpers

// pub fn send(
//   reqs reqs: Reqs(msg),
//   req req: Req(Api, msg),
//   send send: Option(fn(String) -> Effect(msg)),
// ) -> Result(#(Reqs(msg), Effect(msg)), NoConn) {
//   generic_send(reqs:, req:, send:, encode: encode_api)
// }

pub fn req_int_to_string(
  param param: Int,
  msg msg: fn(Result(String, Err)) -> msg,
) -> Req(Api, msg) {
  let req = IntToString
  let decoder = decode.string
  func(param:, msg:, req:, decoder:)
}

// pub fn req_list_items(
//   params params: Option(Params(ItemAttr)),
//   msg msg: fn(Result(Paginated(Item), RecvErr)) -> msg,
// ) -> Req(Api, msg) {
//   let req = Items
//   let decoder = json_paginated_items.decoder()
//   list(params:, msg:, req:, decoder:)
// }

// pub fn req_read_items(
//   id id: Id(Item),
//   msg msg: fn(Result(Record(Item), RecvErr)) -> msg,
// ) -> Req(Api, msg) {
//   let req = Items
//   let decoder = json_items_scalar.decoder()
//   read(id:, msg:, req:, decoder:)
// }

// pub fn req_create_items(
//   data data: Item,
//   msg msg: fn(Result(Record(Item), RecvErr)) -> msg,
// ) -> Req(Api, msg) {
//   let req = Items
//   let decoder = json_items_scalar.decoder()
//   create(data:, msg:, req:, decoder:)
// }

// pub fn req_update_items(
//   id id: Id(Item),
//   data data: Item,
//   msg msg: fn(Result(Record(Item), RecvErr)) -> msg,
// ) -> Req(Api, msg) {
//   let req = Items
//   let decoder = json_items_scalar.decoder()
//   update(id:, data:, msg:, req:, decoder:)
// }

// pub fn req_delete_items(
//   id id: Id(Item),
//   confirm confirm: ConfirmDelete,
//   msg msg: fn(Result(Record(Item), RecvErr)) -> msg,
// ) -> Req(Api, msg) {
//   let req = Items
//   let decoder = json_items_scalar.decoder()
//   delete(id:, confirm:, msg:, req:, decoder:)
// }

// codegen json

const json_paginated_items: Transcoders(Paginated(Item)) =
  Transcoders(
    decoder: decoder_paginated_items,
    encode: encode_paginated_items,
  )

const json_items_scalar: Transcoders(Item) =
  Transcoders(
    decoder: decoder_items_scalar,
    encode: encode_items_scalar,
  )

fn decoder_paginated_items() -> Decoder(Paginated(Item)) {
  todo
}

fn encode_paginated_items(
  value value: Paginated(Item),
) -> Json {
  todo
}

fn decoder_items_scalar() -> Decoder(Item) {
  todo
}

fn encode_items_scalar(
  value value: Item,
) -> Json {
  todo
}

// DERIVED

pub fn encode_api(value: Api) -> Json {
  case value {
    IntToString(..) as value ->
      json.object([#("func", encode_func(value.func, json.int, json.string))])
  }
}

pub fn decoder_api() -> Decoder(Api) {
  decode.one_of(decoder_api_int_to_string(), [])
}

pub fn decoder_api_int_to_string() -> Decoder(Api) {
  use func <- decode.field("func", decoder_func(decode.int, decode.string))
  decode.success(IntToString(func:))
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
