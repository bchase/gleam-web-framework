import youid/uuid.{type Uuid}
import gleam/result
import api/id.{type Id}
import gleam/option.{type Option}
import gleam/io
import gleam/string
import gleam/json.{type Json}
import api/client.{type Api, type Person, type PersonAttr, People, decoder_api, encode_person}
import api/generic.{type Err, List, ListReq, Create, Read, Update, Delete, CreateReq, ReadReq, UpdateReq, DeleteReq, type Params, type Paginated, encode_paginated, encode_record, type Record, type ConfirmDelete, type ListReq, type Crud, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, type SocketReq}

// codegen server

pub type SocketResp {
  SocketResp(
    ref: Uuid,
    resp: Json,
  )
}

pub fn api_server(
  req req: SocketReq(Api),
) -> Result(SocketResp, Err) {
  let generic.SocketReq(ref:, req:) = req

  case req {
    People(crud:) ->
      crud_people
      |> process_crud(crud:, ref:)
  }
}

// domain server impl

pub const crud_people =
  ServerCrudHandler(
    list: list_people,
    create: create_people,
    update: update_people,
    read: read_people,
    delete: delete_people,
    //
    encode: encode_person,
  )

fn list_people(
  req req: ListReq(resource, key),
) -> Result(Paginated(resource), Err) {
  todo
}
fn create_people(
  req req: CreateReq(resource, create),
) -> Result(Record(resource), Err) {
  todo
}
fn update_people(
  req req: UpdateReq(resource, update),
) -> Result(Record(resource), Err) {
  todo
}
fn read_people(
  req req: ReadReq(resource),
) -> Result(Record(resource), Err) {
  todo
}
fn delete_people(
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
  |> result.map(SocketResp(ref:, resp: _))
}
