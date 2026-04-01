import gleam/int
import youid/uuid.{type Uuid}
import gleam/result
import api/id.{type Id}
import gleam/option.{type Option}
import gleam/io
import gleam/string
import gleam/json.{type Json}
import api/client.{type Api, type Item, type ItemAttr, decoder_api, encode_item}
import api/generic.{type Err, List, ListReq, Create, Read, Update, Delete, CreateReq, ReadReq, UpdateReq, DeleteReq, type Params, type Paginated, encode_paginated, encode_record, type Record, type ConfirmDelete, type ListReq, type Crud, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, type SocketReq, type SocketResp, SocketResp, type Func}

// codegen server

pub fn api_server(
  req req: SocketReq(Api),
) -> Result(SocketResp, Err) {
  let generic.SocketReq(ref:, req:) = req

  case req {
    client.Items(crud:) ->
      crud_items
      |> process_crud(crud:, ref:)

    client.IntToString(func:) ->
      func_int_to_string
      |> process_func(func:, ref:)
  }
}

// domain server impl

pub const func_int_to_string =
  ServerFuncHandler(
    run: int_to_string,
    //
    encode: json.string,
  )

fn int_to_string(
  num num: Int,
) -> Result(String, Err) {
  Ok(int.to_string(num))
}

pub const crud_items =
  ServerCrudHandler(
    list: list_items,
    create: create_items,
    update: update_items,
    read: read_items,
    delete: delete_items,
    //
    encode: encode_item,
  )

fn list_items(
  req req: ListReq(resource, key),
) -> Result(Paginated(resource), Err) {
  todo
}
fn create_items(
  req req: CreateReq(resource, create),
) -> Result(Record(resource), Err) {
  todo
}
fn update_items(
  req req: UpdateReq(resource, update),
) -> Result(Record(resource), Err) {
  todo
}
fn read_items(
  req req: ReadReq(resource),
) -> Result(Record(resource), Err) {
  todo
}
fn delete_items(
  req req: DeleteReq(resource),
) -> Result(Record(resource), Err) {
  todo
}

// generic

pub type ServerCrudHandler(resource, create, update, key) {
  ServerCrudHandler(
    list: fn(ListReq(resource, key)) -> Result(Paginated(resource), Err),
    create: fn(CreateReq(resource, create)) -> Result(Record(resource), Err),
    update: fn(UpdateReq(resource, update)) -> Result(Record(resource), Err),
    read: fn(ReadReq(resource)) -> Result(Record(resource), Err),
    delete: fn(DeleteReq(resource)) -> Result(Record(resource), Err),
    //
    encode: fn(resource) -> Json,
  )
}

pub type ServerFuncHandler(param, return) {
  ServerFuncHandler(
    run: fn(param) -> Result(return, Err),
    //
    encode: fn(return) -> Json,
  )
}

pub fn process_func(
  func func: Func(param, return),
  ref ref: Uuid,
  handler handler: ServerFuncHandler(param, return),
) -> Result(SocketResp, Err) {
  func.req.param
  |> handler.run
  |> result.map(handler.encode)
  |> result.map(fn(json) { SocketResp(ref:, result: Ok(json)) })
}

pub fn process_crud(
  crud crud: Crud(resource, create, update, key),
  ref ref: Uuid,
  handler handler: ServerCrudHandler(resource, create, update, key),
) -> Result(SocketResp, Err) {
  case crud {
    List(req:) -> handler.list(req) |> result.map(encode_paginated(_, handler.encode))
    Create(req:) -> handler.create(req) |> result.map(encode_record(_, handler.encode))
    Read(req:) -> handler.read(req) |> result.map(encode_record(_, handler.encode))
    Update(req:) -> handler.update(req) |> result.map(encode_record(_, handler.encode))
    Delete(req:) -> handler.delete(req) |> result.map(encode_record(_, handler.encode))
  }
  |> result.map(fn(json) { SocketResp(ref:, result: Ok(json)) })
}
