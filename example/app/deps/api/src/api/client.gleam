import api/id.{type Id}
import gleam/option.{type Option, Some, None}
import gleam/pair
import gleam/dict.{type Dict}
import gleam/string
import gleam/dynamic.{type Dynamic}
import gleam/result
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import youid/uuid.{type Uuid}
import api/generic.{type Paginated, type SocketReq, SocketReq, type Crud, type Record, List, ListReq, Read, ReadReq, type Pagination}

pub type RecvErr(ref) {
  NoRef(
    json: String,
  )
  RefParseFailure(
    ref: String,
    err: String,
  )
  ReqNotFound(
    ref: ref,
    json: String,
  )
  RespNotFound(
    ref: ref,
    json: String,
  )
  JsonDecodeErr(
    ref: ref,
    err: json.DecodeError,
  )
  // DecodeErrs(
  //   ref: ref,
  //   errs: List(decode.DecodeError),
  // )
}

type Reqs(ref, msg) = Dict(ref, fn(Dynamic) -> Result(msg, RecvErr(ref)))

type NoConn {
  NoConn
}

// RECEIVE

pub fn recv(
  reqs reqs: Reqs(ref, msg),
  json json: String,
  parse parse: fn(String) -> Result(ref, String)
) -> Result(#(Reqs(ref, msg), msg), RecvErr(ref)) {
  use #(ref, resp) <- result.try(recv_(json:, parse:))

  use #(reqs, to_msg) <- result.try(
    pop_req(reqs, ref)
    |> result.replace_error(ReqNotFound(ref:, json:))
  )

  use msg <- result.try(resp |> to_msg)

  Ok(#(reqs, msg))
}

fn pop_req(
  reqs reqs: Reqs(ref, msg),
  ref ref: ref,
) -> Result(#(Reqs(ref, msg), fn(Dynamic) -> Result(msg, RecvErr(ref))), Nil) {
  reqs
  |> dict.get(ref)
  |> result.map(pair.new(dict.delete(reqs, ref), _)) // TODO lazy
}

fn recv_(
  json json: String,
  parse parse: fn(String) -> Result(ref, String)
) -> Result(#(ref, Dynamic), RecvErr(ref)) {
  use ref <- result.try(
    decode.at(["ref"], decode.string)
    |> json.parse(json, _)
    |> result.replace_error(NoRef(json:))
  )

  use ref <- result.try(
    parse(ref)
    |> result.map_error(fn(err) {
      RefParseFailure(ref:, err: err |> string.inspect)
    })
  )

  use resp <- result.try(
    decode.at(["resp"], decode.dynamic)
    |> json.parse(json, _)
    |> result.replace_error(RespNotFound(ref:, json:))
  )

  Ok(#(ref, resp))
}

// SEND

// fn socket_listen(
//   socket socket: NewSocket,
//   req req: NewReq(NewMsg)
// ) -> Result(NewSocket, NoConn) {
//   socket.reqs
//   |> generic_listen(conn: socket.conn, req:)
//   |> result.map(fn(reqs) {
//     NewSocket(..socket, reqs:)
//   })
// }

type Req(req, msg, ref) {
  Req(
    ref: ref,
    req: req,
    // resp: fn(Dynamic) -> Result(msg, RecvErr(ref)),
    resp: fn(Dynamic) -> Result(msg, List(decode.DecodeError)),
  )
}

fn generic_listen(
  reqs reqs: Reqs(ref, msg),
  req req: Req(req, msg, ref),
  encode encode: fn(req) -> Json,
  // make_ref make_ref: fn() -> ref,
  ref_str ref_str: fn(ref) -> String,
  send send: Option(fn(String) -> Nil),
) -> Result(Reqs(ref, msg), NoConn) {
  case send {
    None ->
      Error(NoConn)

    Some(send) -> {
      req.req
      |> SocketReq(ref: ref_str(req.ref))
      |> generic.encode_socket_req(encode)
      |> json.to_string
      |> send

      Ok(dict.insert(reqs, req.ref, todo))
    }
  }
}

// dummy lustre app

type Msg {
  NoOp
}

fn update(
  reqs reqs: Reqs(Uuid, Msg),
  msg msg: Msg,
) -> #(Reqs(Uuid, Msg), Msg) {
  case msg {
    NoOp -> todo
  }
}

// dummy api

type Api {
  People(Crud(Person, Person, Person))
}

type Person {
  Person(
    name: String,
  )
}

type Transcoders(t) {
  Transcoders(
    decoder: fn() -> Decoder(t),
    encode: fn(t) -> Json,
  )
}

fn list(
  pagination pagination: Option(Pagination),
  ref ref: ref,
  msg msg: fn(Paginated(t)) -> msg,
  //
  req req: fn(Crud(t, t, t)) -> req,
  decoder decoder: Decoder(Paginated(t)),
) -> Req(req, msg, ref) {
  build_req(
    req: req(List(ListReq(pagination:))),
    decoder:,
    msg:,
    ref:,
  )
}

fn read(
  id id: Id(t),
  ref ref: ref,
  msg msg: fn(t) -> msg,
  //
  req req: fn(Crud(t, t, t)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg, ref) {
  build_req(
    req: req(Read(ReadReq(id:))),
    decoder:,
    msg:,
    ref:,
  )
}

fn list_people(
  pagination pagination: Option(Pagination),
  ref ref: ref,
  msg msg: fn(Paginated(Person)) -> msg,
) -> Req(Api, msg, ref) {
  list(
    pagination:,
    ref:,
    msg:,
    req: People,
    decoder: json_paginated_people.decoder(),
  )
}

fn req_read_people(
  id id: Id(Person),
  ref ref: ref,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg, ref) {
  build_req(
    req: People(Read(ReadReq(id:))),
    decoder: json_people_scalar.decoder(),
    msg:,
    ref:,
  )
}

fn build_req(
  req req: req,
  decoder decoder: Decoder(t),
  msg msg: fn(t) -> msg,
  ref ref: ref,
) -> Req(req, msg, ref) {
  Req(ref:, req:, resp: fn(dyn) {
    dyn
    |> decode.run(decoder)
    |> result.map(msg)
  })
}

//

const json_paginated_people: Transcoders(Paginated(Person)) =
  Transcoders(
    decoder: decoder_paginated_people,
    encode: encode_paginated_people,
  )

const json_people_scalar: Transcoders(Record(Person)) =
  Transcoders(
    decoder: decoder_people_scalar,
    encode: encode_people_scalar,
  )

fn decoder_paginated_people() -> Decoder(Paginated(Person)) {
  todo
}

fn encode_paginated_people(
  value value: Paginated(Person),
) -> Json {
  todo
}

fn decoder_people_scalar() -> Decoder(Record(Person)) {
  todo
}

fn encode_people_scalar(
  value value: Record(Person),
) -> Json {
  todo
}
