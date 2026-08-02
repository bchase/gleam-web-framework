import fpo/api/ws/types.{type Err, List, Create, Read, Update, Delete, type Paginated, encode_paginated, encode_record, type ListReq, type Crud, type CreateReq, type UpdateReq, type ReadReq, type DeleteReq, type SocketResp, SocketResp, type Func, Created, Updated, Deleted, type Sub, type Record}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import youid/uuid.{type Uuid}

pub type App(t, err, ctx) { App(run: fn(ctx) -> Result(t, err)) }
fn run(app: App(t, err, ctx), ctx: ctx) -> Result(t, err) { app.run(ctx) }
fn pure(x: t) { App(run: fn(_) { Ok(x) }) }
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

// server definition

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

pub type FuncHandler(param, return, listener, msg, context) {
  FuncHandler(
    run: fn(param, context) -> Result(return, Err),
    //
    encode: fn(return) -> Json,
  )
}

// pub type SubHandler1(sub_msg, listener, msg, context) {
//   SubHandler1(
//     run: fn(Sub(sub_msg), Uuid, context, fn(fn(Uuid) -> SocketResp) -> msg) -> Result(listener, Err),
//     //
//     encode: fn(sub_msg) -> Json,
//     sub: Sub(sub_msg),
//     send: fn(SocketResp) -> msg,
//   )
// }

// TODO if eventually in an erlang package, `listener` is actually `process.Selector(msg)`
pub type SubHandler(sub_msg, context, listener, msg) {
  SubHandler(
    run: fn(Sub(sub_msg), context, fn(fn(Uuid) -> SocketResp) -> msg) -> Result(listener, Err),
    //
    encode: fn(sub_msg) -> Json,
    sub: Sub(sub_msg),
  )
}

pub fn func_handler_app(
  app app: fn(param) -> App(return, err, context),
  encode encode: fn(return) -> Json,
  err err: fn(err) -> Err,
) -> FuncHandler(param, return, Nil, Nil, context) {
  FuncHandler(
    run: app_to_func(app:, err:),
    //
    encode:,
  )
}

pub fn sub_socket_resp(
  value value: t,
  encode encode: fn(t) -> Json,
) -> fn(Uuid) -> types.SocketResp {
  fn(ref) {
    types.S(value)
    |> types.encode_subscription_msg(encode)
    // types.S(Ok(value))
    // |> types.encode_subscription_msg(
    //   types.encode_result(_, encode, fn(_) { json.null() })
    // )
    |> Ok
    |> types.SocketResp(ref:, action: None)
  }
}

pub type Return(listener) {
  Return(
    resp: SocketResp,
    subs: Set(String),
    listener: Option(listener),
  )
}

pub fn process_sub(
  sub sub: Sub(sub_msg),
  ref ref: Uuid,
  ctx ctx: context,
  subs subs: Set(String),
  handler handler: SubHandler(sub_msg, context, listener, msg),
  wrap wrap: fn(SocketResp) -> msg,
) -> Return(listener) {
  let action = None

  let sub_str = sub |> string.inspect

  case set.contains(subs, sub_str)  {
    True -> {
      let resp = SocketResp(ref:, action:, result: Error(types.Server(types.ServerErr("already subscribed: " <> sub_str))))
      Return(resp:, subs:, listener: None)
    }

    False ->
      case handler.run(sub, ctx, fn(to_resp) { ref |> to_resp |> wrap }) {
        Ok(listener) -> {
          let ack =
            types.S(Ok(Nil))
            |> types.encode_subscription_msg(
              types.encode_result(_, types.encode_nil, fn(_) { json.null() })
            )

          let resp = SocketResp(ref:, action:, result: Ok(ack))
          Return(resp:, subs:, listener: Some(listener))
        }

        Error(err) -> {
          let resp = SocketResp(ref:, action:, result: Error(err))
          Return(resp:, subs:, listener: None)
        }
      }
  }
}

pub fn process_func(
  func func: Func(param, return),
  ref ref: Uuid,
  ctx ctx: context,
  subs subs: Set(String),
  handler handler: FuncHandler(param, return, Nil, Nil, context),
) -> Return(listener) {
  let action = None

  let resp =
    case handler.run(func.req.param, ctx) {
      Ok(x) ->
        SocketResp(ref:, action:, result: Ok(handler.encode(x)))

      Error(err) ->
        SocketResp(ref:, action:, result: Error(err))
    }

  Return(resp:, subs:, listener: None)
}

pub fn process_crud(
  crud crud: Crud(resource, create, update, key),
  ref ref: Uuid,
  ctx ctx: context,
  subs subs: Set(String),
  handler handler: CrudHandler(resource, create, update, key, context),
) -> Return(listener) {
  let #(result, action) =
    case crud {
      List(req:) -> #(handler.list(req, ctx) |> result.map(encode_paginated(_, handler.encode)), None)
      Create(req:) -> #(handler.create(req, ctx) |> result.map(encode_record(_, handler.encode)), Some(Created))
      Read(req:) -> #(handler.read(req, ctx) |> result.map(encode_record(_, handler.encode)), None)
      Update(req:) -> #(handler.update(req, ctx) |> result.map(encode_record(_, handler.encode)), Some(Updated))
      Delete(req:) -> #(handler.delete(req, ctx) |> result.map(encode_record(_, handler.encode)), Some(Deleted))
    }

  let resp =
    case result {
      Ok(x) ->
        SocketResp(ref:, action:, result: Ok(x))

      Error(err) ->
        SocketResp(ref:, action:, result: Error(err))
    }

  Return(resp:, subs:, listener: None)
}
