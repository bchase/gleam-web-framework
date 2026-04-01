import gleam/time/timestamp
import gleam/function
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
  ctx ctx,
) -> Result(SocketResp, Err) {
  let generic.SocketReq(ref:, req:) = req

  case req {
    client.Items(crud:) ->
      crud_items()
      |> process_crud(crud:, ref:, ctx:)

    client.IntToString(func:) ->
      func_int_to_string()
      |> process_func(func:, ref:, ctx:)
  }
}

pub type App(t, err, ctx) { App(run: fn(ctx) -> Result(t, err)) }
fn run(app: App(t, err, ctx), ctx: ctx) -> Result(t, err) { todo }
fn pure(x: t) { App(run: fn(_) { Ok(x) }) }
// fn to_app(
//   f f: fn(SocketReq(api), ctx) ->
// )
fn app_to_func(
  app app: fn(param) -> App(return, err, context),
  err err: fn(err) -> Err,
) -> fn(param, context) -> Result(return, Err) {
  fn(input, ctx) {
    input
    |> app
    |> run(ctx)
    |> result.map_error(err)
  }
}

// domain server impl

pub fn func_int_to_string() -> FuncHandler(Int, String, Context) {
  FuncHandler(
    run: int_to_string,
    //
    encode: json.string,
  )
}

fn int_to_string(
  num num: Int,
  ctx ctx: Context,
) -> Result(String, Err) {
  Ok(int.to_string(num))
}

pub type Context {
  Context(
  )
}

pub fn crud_items() -> CrudHandler(Item, Item, Item, ItemAttr, Context) {
  CrudHandler(
    // list: list_items,
    list: list_items_app |> app_to_func(err: function.identity),
    create: create_items,
    update: update_items,
    read: read_items,
    delete: delete_items,
    //
    encode: encode_item,
  )
}

fn list_items_app(
  req req: ListReq(Item, key),
) -> App(Paginated(Item), Err, Context) {
  todo
}
fn list_items(
  req req: ListReq(Item, key),
  ctx ctx,
) -> Result(Paginated(Item), Err) {
  todo
}
fn create_items(
  req req: CreateReq(Item, create),
  ctx ctx,
) -> Result(Record(Item), Err) {
  todo
}
fn update_items(
  req req: UpdateReq(Item, update),
  ctx ctx,
) -> Result(Record(Item), Err) {
  todo
}
fn read_items(
  req req: ReadReq(Item),
  ctx ctx,
) -> Result(Record(Item), Err) {
  {
    let ts = timestamp.system_time()
    pure(generic.Record(
      id: id.Id(""),
      created_at: ts,
      updated_at: ts,
      resource: client.Item(name: ""),
    ))
  }
  |> run(ctx)
}
fn delete_items(
  req req: DeleteReq(Item),
  ctx ctx,
) -> Result(Record(Item), Err) {
  todo
}

// generic

pub type CrudHandler(resource, create, update, key, context) {
  CrudHandler(
    list: fn(ListReq(resource, key), context) -> Result(Paginated(resource), Err),
    create: fn(CreateReq(resource, create), context) -> Result(Record(resource), Err),
    update: fn(UpdateReq(resource, update), context) -> Result(Record(resource), Err),
    read: fn(ReadReq(resource), context) -> Result(Record(resource), Err),
    delete: fn(DeleteReq(resource), context) -> Result(Record(resource), Err),
    //
    encode: fn(resource) -> Json,
  )
}

pub fn crud_handler_app(
  list list: fn(ListReq(resource, key)) -> App(Paginated(resource), err, context),
  create create: fn(CreateReq(resource, create)) -> App(Record(resource), err, context),
  update update: fn(UpdateReq(resource, update)) -> App(Record(resource), err, context),
  read read: fn(ReadReq(resource)) -> App(Record(resource), err, context),
  delete delete: fn(DeleteReq(resource)) -> App(Record(resource), err, context),
  encode encode: fn(resource) -> Json,
  err err: fn(err) -> Err,
) -> CrudHandler(resource, create, update, key, context) {
  CrudHandler(
    list: list |> app_to_func(err:),
    create: create |> app_to_func(err:),
    update: update |> app_to_func(err:),
    read: read |> app_to_func(err:),
    delete: delete |> app_to_func(err:),
    //
    encode:,
  )
}

pub type FuncHandler(param, return, context) {
  FuncHandler(
    run: fn(param, context) -> Result(return, Err),
    //
    encode: fn(return) -> Json,
  )
}

pub fn func_handler_app(
  app app: fn(param) -> App(return, err, context),
  encode encode: fn(return) -> Json,
  err err: fn(err) -> Err,
) -> FuncHandler(param, return, context) {
  FuncHandler(
    run: app_to_func(app:, err:),
    //
    encode:,
  )
}

pub fn process_func(
  func func: Func(param, return),
  ref ref: Uuid,
  ctx ctx: context,
  handler handler: FuncHandler(param, return, context),
) -> Result(SocketResp, Err) {
  func.req.param
  |> handler.run(ctx)
  |> result.map(handler.encode)
  |> result.map(fn(json) { SocketResp(ref:, result: Ok(json)) })
}

pub fn process_crud(
  crud crud: Crud(resource, create, update, key),
  ref ref: Uuid,
  ctx ctx: context,
  handler handler: CrudHandler(resource, create, update, key, context),
) -> Result(SocketResp, Err) {
  case crud {
    List(req:) -> handler.list(req, ctx) |> result.map(encode_paginated(_, handler.encode))
    Create(req:) -> handler.create(req, ctx) |> result.map(encode_record(_, handler.encode))
    Read(req:) -> handler.read(req, ctx) |> result.map(encode_record(_, handler.encode))
    Update(req:) -> handler.update(req, ctx) |> result.map(encode_record(_, handler.encode))
    Delete(req:) -> handler.delete(req, ctx) |> result.map(encode_record(_, handler.encode))
  }
  |> result.map(fn(json) { SocketResp(ref:, result: Ok(json)) })
}
