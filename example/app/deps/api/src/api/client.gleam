import api/generic.{type ConfirmDelete, type Crud, type Paginated, type Pagination, type Params, type Record, type SocketReq, Create, CreateReq, Delete, DeleteReq, List, ListReq, Read, ReadReq, SocketReq, Update, UpdateReq, decoder_crud, decoder_record, encode_crud, encode_record}
import api/id.{type Id}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import youid/uuid.{type Uuid}

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

pub type NoConn {
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

pub type Req(req, msg, ref) {
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

fn dummy_update(
  reqs reqs: Reqs(Uuid, Msg),
  msg msg: Msg,
) -> #(Reqs(Uuid, Msg), Msg) {
  case msg {
    NoOp -> todo
  }
}

// dummy api

pub type PersonAttr {
  //$ derive json encode decode
  PersonName
}

pub type Api {
  //$ derive json encode decode
  People(crud: Crud(Person, Person, Person, PersonAttr))
}

pub type Person {
  //$ derive json encode decode
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
  params params: Option(Params(key)),
  ref ref: ref,
  msg msg: fn(Paginated(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(Paginated(t)),
) -> Req(req, msg, ref) {
  let req = req(List(ListReq(params:)))
  build_req(req:, decoder:, msg:, ref:)
}

fn read(
  id id: Id(t),
  ref ref: ref,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg, ref) {
  let req = req(Read(ReadReq(id:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn create(
  data data: create,
  ref ref: ref,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg, ref) {
  let req = req(Create(CreateReq(data:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn update(
  id id: Id(t),
  data data: update,
  ref ref: ref,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg, ref) {
  let req = req(Update(UpdateReq(id:, data:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn delete(
  id id: Id(t),
  confirm confirm: ConfirmDelete,
  ref ref: ref,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg, ref) {
  let req = req(Delete(DeleteReq(id:, confirm:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
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

// codegen helpers

pub fn listen(
  reqs reqs: Reqs(ref, msg),
  req req: Req(Api, msg, ref),
  ref_str ref_str: fn(ref) -> String,
  send send: Option(fn(String) -> Nil),
) -> Result(Reqs(ref, msg), NoConn) {
  let encode = encode_api
  generic_listen(reqs:, req:, encode:, ref_str:, send:)
}

pub fn list_people(
  params params: Option(Params(PersonAttr)),
  ref ref: ref,
  msg msg: fn(Paginated(Person)) -> msg,
) -> Req(Api, msg, ref) {
  let req = People
  let decoder = json_paginated_people.decoder()
  list(params:, ref:, msg:, req:, decoder:)
}

pub fn read_people(
  id id: Id(Person),
  ref ref: ref,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg, ref) {
  let req = People
  let decoder = json_people_scalar.decoder()
  read(id:, ref:, msg:, req:, decoder:)
}

pub fn create_people(
  data data: Person,
  ref ref: ref,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg, ref) {
  let req = People
  let decoder = json_people_scalar.decoder()
  create(data:, ref:, msg:, req:, decoder:)
}

pub fn update_people(
  id id: Id(Person),
  data data: Person,
  ref ref: ref,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg, ref) {
  let req = People
  let decoder = json_people_scalar.decoder()
  update(id:, data:, ref:, msg:, req:, decoder:)
}

pub fn delete_people(
  id id: Id(Person),
  confirm confirm: ConfirmDelete,
  ref ref: ref,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg, ref) {
  let req = People
  let decoder = json_people_scalar.decoder()
  delete(id:, confirm:, ref:, msg:, req:, decoder:)
}

// codegen json

const json_paginated_people: Transcoders(Paginated(Person)) =
  Transcoders(
    decoder: decoder_paginated_people,
    encode: encode_paginated_people,
  )

const json_people_scalar: Transcoders(Person) =
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

fn decoder_people_scalar() -> Decoder(Person) {
  todo
}

fn encode_people_scalar(
  value value: Person,
) -> Json {
  todo
}

// DERIVED

pub fn encode_person_attr(value: PersonAttr) -> Json {
  case value {
    PersonName -> json.object([])
  }
}

pub fn decoder_person_attr() -> Decoder(PersonAttr) {
  decode.one_of(decoder_person_attr_person_name(), [])
}

pub fn decoder_person_attr_person_name() -> Decoder(PersonAttr) {
  decode.success(PersonName)
}

pub fn encode_api(value: Api) -> Json {
  case value {
    People(..) as value ->
      json.object([
        #(
          "crud",
          encode_crud(
            value.crud,
            encode_person,
            encode_person,
            encode_person,
            encode_person_attr,
          ),
        ),
      ])
  }
}

pub fn decoder_api() -> Decoder(Api) {
  decode.one_of(decoder_api_people(), [])
}

pub fn decoder_api_people() -> Decoder(Api) {
  use crud <- decode.field(
    "crud",
    decoder_crud(
      decoder_person(),
      decoder_person(),
      decoder_person(),
      decoder_person_attr(),
    ),
  )
  decode.success(People(crud:))
}

pub fn encode_person(value: Person) -> Json {
  case value {
    Person(..) as value -> json.object([#("name", json.string(value.name))])
  }
}

pub fn decoder_person() -> Decoder(Person) {
  decode.one_of(decoder_person_person(), [])
}

pub fn decoder_person_person() -> Decoder(Person) {
  use name <- decode.field("name", decode.string)
  decode.success(Person(name:))
}
