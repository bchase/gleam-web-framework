import gleam/io
import lustre/effect.{type Effect}
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
  RespNotFound(
    ref: Uuid,
    json: String,
  )
  JsonDecodeErr(
    ref: Uuid,
    err: json.DecodeError,
  )
  // DecodeErrs(
  //   ref: Uuid,
  //   errs: List(decode.DecodeError),
  // )
}

type Reqs(msg) = Dict(Uuid, fn(Dynamic) -> Result(msg, RecvErr))

pub type NoConn {
  NoConn
}

//

pub type ApiClient(req, model, msg) {
  ApiClient(
    send: fn(model, Req(req, msg)) -> Result(Dict(Uuid, fn(Dynamic) -> Result(msg, RecvErr)), NoConn),
    recv: fn(model, String) -> #(model, Effect(msg)),
  )
}

fn send_and_recv(
  get_reqs get_reqs: fn(model) -> Reqs(msg),
  set_reqs set_reqs: fn(model, Reqs(msg)) -> model,
  //
  get_send get_send: fn(model) -> Option(fn(String) -> Nil),
  // recv
  json json: String,
  parse parse: fn(String) -> Result(Uuid, String),
  err to_err_msg: fn(RecvErr) -> Option(msg),
  // send
  encode encode: fn(req) -> Json,
// ) -> ApiClient(req, model, msg) {
) -> ApiClient(req, model, msg) {
  let send =
    fn(model, req) {
      let reqs = get_reqs(model)
      let send = get_send(model)
      generic_send(req:, reqs:, send:, encode:)
    }

  let recv =
    fn(model, json) {
      let reqs = get_reqs(model)
      case generic_recv(json:, reqs:, parse:) {
        Ok(#(reqs, msg)) ->
          model
          |> set_reqs(reqs)
          |> pair.new(effect.from(fn(dispatch) {
            dispatch(msg)
          }))

        Error(err) -> {
          io.println_error("`RecvErr`:\n" <> err |> string.inspect)

          let reqs =
            case err {
              NoRef(..) |
              RefParseFailure(..) ->
                reqs

              ReqNotFound(ref:, ..) |
              RespNotFound(ref:, ..) |
              JsonDecodeErr(ref:, ..) ->
                case pop_req(reqs, ref) {
                  Error(Nil) ->
                    reqs

                  Ok(#(reqs, _req)) ->
                    reqs
                }
            }

          let model =
            model
            |> set_reqs(reqs)

          case to_err_msg(err) {
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
    }

  ApiClient(send:, recv:)
}

// RECEIVE

fn generic_recv(
  reqs reqs: Reqs(msg),
  json json: String,
  parse parse: fn(String) -> Result(Uuid, String),
) -> Result(#(Reqs(msg), msg), RecvErr) {
  use #(ref, resp) <- result.try(recv_(json:, parse:))

  use #(reqs, to_msg) <- result.try(
    pop_req(reqs, ref)
    |> result.replace_error(ReqNotFound(ref:, json:))
  )

  use msg <- result.try(resp |> to_msg)

  Ok(#(reqs, msg))
}

fn pop_req(
  reqs reqs: Reqs(msg),
  ref ref: Uuid,
) -> Result(#(Reqs(msg), fn(Dynamic) -> Result(msg, RecvErr)), Nil) {
  reqs
  |> dict.get(ref)
  |> result.map(pair.new(dict.delete(reqs, ref), _)) // TODO lazy
}

fn recv_(
  json json: String,
  parse parse: fn(String) -> Result(Uuid, String)
) -> Result(#(Uuid, Dynamic), RecvErr) {
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

pub type Req(req, msg) {
  Req(
    ref: Uuid,
    req: req,
    // resp: fn(Dynamic) -> Result(msg, RecvErr(ref)),
    resp: fn(Dynamic) -> Result(msg, List(decode.DecodeError)),
  )
}

fn generic_send(
  reqs reqs: Reqs(msg),
  req req: Req(req, msg),
  send send: Option(fn(String) -> Nil),
  encode encode: fn(req) -> Json,
) -> Result(Reqs(msg), NoConn) {
  case send {
    None ->
      Error(NoConn)

    Some(send) -> {
      req.req
      |> SocketReq(ref: req.ref |> uuid.to_string)
      |> generic.encode_socket_req(encode)
      |> json.to_string
      |> send

      Ok(dict.insert(reqs, req.ref, todo))
    }
  }
}

// dummy lustre app

type Model {
  Model(
    reqs: Reqs(Msg)
  )
}

type Msg {
  NoOp
}

fn dummy_model(
  reqs reqs: Reqs(Msg),
  msg msg: Msg,
) -> Model {
  todo
}

fn dummy_update(
  reqs reqs: Reqs(Msg),
  msg msg: Msg,
) -> #(Reqs(Msg), Msg) {
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
  ref ref: Uuid,
  msg msg: fn(Paginated(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(Paginated(t)),
) -> Req(req, msg) {
  let req = req(List(ListReq(params:)))
  build_req(req:, decoder:, msg:, ref:)
}

fn read(
  id id: Id(t),
  ref ref: Uuid,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg) {
  let req = req(Read(ReadReq(id:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn create(
  data data: create,
  ref ref: Uuid,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg) {
  let req = req(Create(CreateReq(data:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn update(
  id id: Id(t),
  data data: update,
  ref ref: Uuid,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg) {
  let req = req(Update(UpdateReq(id:, data:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn delete(
  id id: Id(t),
  confirm confirm: ConfirmDelete,
  ref ref: Uuid,
  msg msg: fn(Record(t)) -> msg,
  //
  req req: fn(Crud(t, create, update, key)) -> req,
  decoder decoder: Decoder(t),
) -> Req(req, msg) {
  let req = req(Delete(DeleteReq(id:, confirm:)))
  let decoder = decoder_record(decoder)
  build_req(req:, decoder:, msg:, ref:)
}

fn build_req(
  req req: req,
  decoder decoder: Decoder(t),
  msg msg: fn(t) -> msg,
  ref ref: Uuid,
) -> Req(req, msg) {
  Req(ref:, req:, resp: fn(dyn) {
    dyn
    |> decode.run(decoder)
    |> result.map(msg)
  })
}

// codegen helpers

pub fn send(
  reqs reqs: Reqs(msg),
  req req: Req(Api, msg),
  send send: Option(fn(String) -> Nil),
) -> Result(Reqs(msg), NoConn) {
  generic_send(reqs:, req:, send:, encode: encode_api)
}

pub fn list_people(
  params params: Option(Params(PersonAttr)),
  ref ref: Uuid,
  msg msg: fn(Paginated(Person)) -> msg,
) -> Req(Api, msg) {
  let req = People
  let decoder = json_paginated_people.decoder()
  list(params:, ref:, msg:, req:, decoder:)
}

pub fn read_people(
  id id: Id(Person),
  ref ref: Uuid,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg) {
  let req = People
  let decoder = json_people_scalar.decoder()
  read(id:, ref:, msg:, req:, decoder:)
}

pub fn create_people(
  data data: Person,
  ref ref: Uuid,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg) {
  let req = People
  let decoder = json_people_scalar.decoder()
  create(data:, ref:, msg:, req:, decoder:)
}

pub fn update_people(
  id id: Id(Person),
  data data: Person,
  ref ref: Uuid,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg) {
  let req = People
  let decoder = json_people_scalar.decoder()
  update(id:, data:, ref:, msg:, req:, decoder:)
}

pub fn delete_people(
  id id: Id(Person),
  confirm confirm: ConfirmDelete,
  ref ref: Uuid,
  msg msg: fn(Record(Person)) -> msg,
) -> Req(Api, msg) {
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
