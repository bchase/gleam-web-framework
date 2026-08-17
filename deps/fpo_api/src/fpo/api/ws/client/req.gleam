import fpo/api/ws/types.{type Id, type Action, type ConfirmDelete, type Crud, type Func, type Paginated, type Params, type Record, type Sub, Sub, Create, CreateReq, Delete, DeleteReq, Func, FuncReq, List, ListReq, Read, ReadReq, SocketReq, Update, UpdateReq, decoder_record}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/io
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/effect.{type Effect}
import youid/uuid.{type Uuid}

pub opaque type Req(req, msg) {
  Req(
    ref: Uuid,
    req: req,
    resp: HandlerFunc(msg),
  )
}

pub opaque type Reqs(msg) {
  Reqs(
    dict: Dict(Uuid, HandlerFunc(msg)),
  )
}

pub fn empty_reqs() -> Reqs(msg) {
  Reqs(dict: dict.new())
}

pub type HandlerFunc(msg) = fn(Dynamic) -> HandlerResult(msg)

pub type HandlerResult(msg) = Result(msg, RecvErr)
// pub type HandlerResult(msg) {
//   HandlerResult(
//     result: Result(msg, RecvErr),
//     err: fn(RecvErr) -> msg,
//   )
// }

pub type Err {
  ApiErr(err: types.Err)
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
  DecodeErrs(
    ref: Uuid,
    errs: List(decode.DecodeError),
  )
}

pub type NoConn {
  NoConn
}

// REQS

pub fn get_req(
  reqs reqs: Reqs(msg),
  ref ref: Uuid,
) -> Result(#(Reqs(msg), HandlerFunc(msg)), Nil) {
  use f <- result.try(dict.get(reqs.dict, ref))
  Ok(#(reqs, f))
}

pub fn pop_req(
  reqs reqs: Reqs(msg),
  ref ref: Uuid,
) -> Result(#(Reqs(msg), HandlerFunc(msg)), Nil) {
  use f <- result.try(dict.get(reqs.dict, ref))

  let reqs = Reqs(dict: dict.delete(reqs.dict, ref))

  Ok(#(reqs, f))
}

pub fn insert_req(
  reqs reqs: Reqs(msg),
  req req: Req(req, msg),
) -> Reqs(msg) {
  Reqs(dict: reqs.dict |> dict.insert(req.ref, req.resp))
}

pub fn clear_req_and_log_err(
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

pub fn send(
  reqs reqs: Reqs(msg),
  req req: Req(req, msg),
  send send: Option(fn(String) -> Effect(msg)),
  encode encode: fn(req) -> Json,
) -> Result(#(Reqs(msg), Effect(msg)), NoConn) {
  case send {
    None ->
      Error(NoConn)

    Some(send) -> {
      let reqs = insert_req(reqs, req)

      let send_eff =
        req.req
        |> SocketReq(ref: req.ref)
        |> types.encode_socket_req(encode)
        |> json.to_string
        |> send

      Ok(#(reqs, send_eff))
    }
  }
}

// DEFINITION HELPERS

pub fn func(
  req req: fn(Func(param, return)) -> req,
  param param: param,
  decoder decoder: Decoder(return),
  msg msg: fn(Result(return, Err)) -> msg,
) -> Req(req, msg) {
  let req = req(Func(FuncReq(param:)))
  let err = fn(err) { msg(Error(RecvErr(err))) }
  build_req(req:, decoder:, msg:, err:)
}

pub fn sub(
  req req: fn(Sub(t)) -> req,
  decoder decoder: Decoder(t),
  msg msg: fn(t) -> msg,
) -> Req(req, msg) {
  let req = req(Sub)
  let ref = uuid.v7()
  Req(ref:, req:, resp: fn(dyn) {
    dyn
    |> decode.run(decoder)
    |> result.map_error(DecodeErrs(ref:, errs: _))
    |> result.map(msg)
    // |> todo
    // |> HandlerResult(result: _, err: fn(err) { msg(RecvErr(err)) })
    // |> HandlerResult(result: _, err: todo as "tk")
  })
}

pub fn list(
  req req: fn(Crud(t, create, update, key)) -> req,
  params params: Option(Params(key)),
  decoder decoder: Decoder(t),
  msg msg: fn(Result(Paginated(t), Err)) -> msg,
) -> Req(req, msg) {
  let req = req(List(ListReq(params:)))
  let err = fn(err) { msg(Error(RecvErr(err))) }
  let decoder = types.decoder_paginated(decoder)
  build_req(req:, decoder:, msg:, err:)
}

pub fn read(
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

pub fn create(
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

pub fn update(
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

pub fn delete(
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

pub fn build_req(
  req req: req,
  decoder decoder: Decoder(t),
  msg msg: fn(Result(t, Err)) -> msg,
  err err: fn(RecvErr) -> msg
) -> Req(req, msg) {
  let ref = uuid.v7()
  Req(ref:, req:, resp: fn(dyn) {
    dyn
    |> decode.run(types.decoder_result(decoder, types.decoder_err()))
    |> result.map(result.map_error(_, ApiErr))
    |> result.map(msg)
    |> result.map_error(DecodeErrs(ref:, errs: _))
  })
}

pub const paginated = types.decoder_paginated

pub fn action(
  msg msg: fn(#(Action, Result(Record(t), Err))) -> msg,
  action action: Action,
) -> fn(Result(Record(t), Err)) -> msg {
  fn(result) { msg(#(action, result)) }
}

pub fn map(
  req req: Req(req, msg1),
  apply f: fn(msg1) -> msg2,
) -> Req(req, msg2) {
  Req(..req, resp: fn(dyn) {
    dyn
    |> req.resp
    |> result.map(f)
  })
}
